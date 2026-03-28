// ============================================================================
// Module 04: DNS & Connectivity
// AZ-104 Certification Lab — Azure DNS, Private DNS, UDRs, Service Endpoints,
// Private Endpoints, Azure Bastion
// ============================================================================
// This module deploys connectivity and name-resolution resources that build on
// the hub-spoke topology from Modules 00 and 03. It covers 15–20% of the
// AZ-104 exam (virtual networking domain).
//
// IMPORTANT: Deploy this module into the SAME resource group as Module 03
// (rg-az104-lab-networking) because it modifies existing spoke subnets via the
// Bicep 'existing' keyword. DNS zones are global and work from any RG.
// ============================================================================

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources. DNS zones are global and ignore this, but route tables, Bastion, and endpoints are regional.')
param location string = 'eastus'

@description('Environment tag applied to every resource. Useful for cost tracking and policy enforcement — both AZ-104 topics.')
param environment string = 'az104-lab'

@description('Resource ID of the hub virtual network (output from Module 00). Used for Private DNS VNet link and Bastion subnet derivation.')
param hubVNetId string

@description('Resource ID of the Spoke 1 virtual network (output from Module 03). Used for Private DNS VNet link and existing-VNet subnet references.')
param spoke1VNetId string

@description('Resource ID of Spoke 1 data subnet (output from Module 03). Used for private endpoint placement. Format: /subscriptions/.../subnets/data')
param spoke1DataSubnetId string

@description('Resource ID of a storage account to create a private endpoint for (output from Module 06). Leave empty to skip private endpoint deployment.')
param storageAccountResourceId string = ''

@description('Deploy Azure Bastion into the hub VNet AzureBastionSubnet. Bastion Basic SKU costs ~$0.19/hr — deploy only when actively needed, then delete to save costs.')
param deployBastion bool = true

@description('Deploy a private endpoint for the storage account blob service. Requires storageAccountResourceId to be provided (from Module 06).')
param deployPrivateEndpoint bool = false

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

@description('Standard tags applied to every resource in this module for consistent governance.')
var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'dns-connectivity'
}

@description('Spoke 1 VNet name extracted from its resource ID for existing-VNet subnet operations.')
var spoke1VNetName = last(split(spoke1VNetId, '/'))

@description('Bastion subnet ID derived from the hub VNet. Azure requires the subnet be named exactly AzureBastionSubnet.')
var bastionSubnetId = '${hubVNetId}/subnets/AzureBastionSubnet'

// Subnet address prefixes — must match Module 03 definitions.
// If Module 03 uses different prefixes, update these variables to match.
var spoke1DefaultSubnetPrefix = '10.1.0.0/24'
var spoke1DataSubnetPrefix = '10.1.4.0/24'

// ============================================================================
// PUBLIC DNS ZONE
// ============================================================================
// Azure DNS hosts your domain's DNS records on Azure's global anycast network.
// AZ-104 tests: zone creation, record types (A, AAAA, CNAME, MX, TXT, SRV,
// NS, SOA), TTL, alias records, delegation, and split-horizon DNS.
// ============================================================================

@description('''
Public DNS zone for az104-lab.example.com. This is a learning zone — it won't resolve
publicly unless you own the domain and delegate its NS records to Azure DNS name servers.
To delegate: create NS records at your registrar pointing to the Azure-assigned name servers
(see the publicDnsZoneNameServers output).
''')
resource publicDnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: 'az104-lab.example.com'
  location: 'global'
  tags: commonTags
  properties: {
    zoneType: 'Public'
  }
}

@description('A record: www.az104-lab.example.com → 10.1.0.4 (example web server IP in Spoke 1).')
resource dnsARecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  parent: publicDnsZone
  name: 'www'
  properties: {
    TTL: 3600
    ARecords: [
      { ipv4Address: '10.1.0.4' }
    ]
  }
}

@description('CNAME record: portal.az104-lab.example.com → www.az104-lab.example.com. CNAME creates an alias to another DNS name.')
resource dnsCnameRecord 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  parent: publicDnsZone
  name: 'portal'
  properties: {
    TTL: 3600
    CNAMERecord: {
      cname: 'www.az104-lab.example.com'
    }
  }
}

@description('TXT record at zone apex (@): SPF record for email authentication (example). TXT records store arbitrary text — commonly used for SPF, DKIM, and domain verification.')
resource dnsTxtRecord 'Microsoft.Network/dnsZones/TXT@2018-05-01' = {
  parent: publicDnsZone
  name: '@'
  properties: {
    TTL: 3600
    TXTRecords: [
      { value: ['v=spf1 include:example.com ~all'] }
    ]
  }
}

// ============================================================================
// PRIVATE DNS ZONE
// ============================================================================
// Azure Private DNS provides name resolution within virtual networks without
// needing a custom DNS solution. VNet links control which VNets can resolve
// records in the zone. Auto-registration creates A records for VMs automatically.
// AZ-104 tests: private zones, VNet links, auto-registration, split-horizon.
// ============================================================================

@description('''
Private DNS zone for internal name resolution across the hub-spoke topology.
Resources in linked VNets resolve names like db.az104-lab.internal to private IPs.
Only ONE VNet link per zone can have auto-registration enabled per VNet.
''')
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'az104-lab.internal'
  location: 'global'
  tags: commonTags
}

@description('Link Private DNS zone to the hub VNet with auto-registration ENABLED. VMs deployed into the hub VNet automatically get A records created in az104-lab.internal.')
resource privateDnsHubLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-hub'
  location: 'global'
  tags: commonTags
  properties: {
    virtualNetwork: { id: hubVNetId }
    registrationEnabled: true
  }
}

@description('Link Private DNS zone to Spoke 1 VNet with auto-registration DISABLED. Spoke 1 resources can resolve names but won\'t auto-register — records must be created manually.')
resource privateDnsSpoke1Link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'link-spoke1'
  location: 'global'
  tags: commonTags
  properties: {
    virtualNetwork: { id: spoke1VNetId }
    registrationEnabled: false
  }
}

@description('Manual A record: db.az104-lab.internal → 10.1.2.4 (example database server in Spoke 1 App subnet).')
resource privateDnsARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'db'
  properties: {
    ttl: 3600
    aRecords: [
      { ipv4Address: '10.1.2.4' }
    ]
  }
}

// ============================================================================
// ROUTE TABLE & USER-DEFINED ROUTES (UDRs)
// ============================================================================
// UDRs override Azure's default system routes. Common use: force traffic through
// a Network Virtual Appliance (NVA) like Azure Firewall for inspection.
// AZ-104 tests: UDRs, next hop types (VirtualAppliance, VNetGateway, Internet,
// None, VirtualNetwork), BGP route propagation, effective routes.
// ============================================================================

@description('''
Route table for Spoke 1 with a UDR that forces all internet-bound traffic (0.0.0.0/0)
through a virtual appliance at 10.0.3.4 (hub AzureFirewallSubnet). This simulates a
common enterprise pattern where an NVA inspects all egress traffic.
disableBgpRoutePropagation: false — allows BGP routes from a VPN gateway to propagate.
''')
resource routeTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'rt-az104-lab-spoke1'
  location: location
  tags: commonTags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'to-internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: '10.0.3.4'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Subnet Associations (Route Table + Service Endpoints)
// ---------------------------------------------------------------------------
// Associating a route table or enabling service endpoints requires updating
// the existing subnet resource. We reference the VNet with the 'existing'
// keyword and redeclare the subnets with the added properties.
//
// ⚠️  CAVEATS:
//   1. This module MUST be deployed to the same resource group as Module 03.
//   2. The addressPrefix values MUST match Module 03's subnet definitions.
//   3. Redeclaring a subnet replaces all its properties. If Module 03 sets
//      NSGs, delegations, or other config, include them here too.
//
// CLI ALTERNATIVE (works cross-resource-group):
//   az network vnet subnet update -g rg-az104-lab-networking \
//     --vnet-name vnet-az104-lab-spoke1 -n default --route-table rt-az104-lab-spoke1
//   az network vnet subnet update -g rg-az104-lab-networking \
//     --vnet-name vnet-az104-lab-spoke1 -n data --service-endpoints Microsoft.Storage
// ---------------------------------------------------------------------------

@description('Reference to the existing Spoke 1 VNet from Module 03. Must be in the same resource group as this deployment.')
resource spoke1VNet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: spoke1VNetName
}

@description('''
Associate the route table with Spoke 1 default subnet. All traffic from this subnet
to 0.0.0.0/0 will now be routed through the NVA at 10.0.3.4 instead of directly to
the internet. Verify with: az network nic show-effective-route-table.
''')
resource spoke1DefaultSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: spoke1VNet
  name: 'default'
  properties: {
    addressPrefix: spoke1DefaultSubnetPrefix
    routeTable: {
      id: routeTable.id
    }
  }
}

@description('''
Enable Microsoft.Storage service endpoint on Spoke 1 data subnet. Service endpoints
provide optimised, direct connectivity to Azure PaaS services over the Azure backbone
network — traffic never leaves the Microsoft network. Combine with storage account
firewall rules to restrict access to this subnet only.
AZ-104: service endpoints vs private endpoints — know the differences!
''')
resource spoke1DataSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: spoke1VNet
  name: 'data'
  dependsOn: [spoke1DefaultSubnet] // Serialise subnet operations on the same VNet
  properties: {
    addressPrefix: spoke1DataSubnetPrefix
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
    ]
  }
}

// ============================================================================
// PRIVATE ENDPOINT FOR STORAGE
// ============================================================================
// Private endpoints assign a private IP from your VNet to a PaaS service,
// making it accessible as if it were deployed inside the VNet. Combined with
// a private DNS zone, clients resolve the service FQDN to the private IP.
// AZ-104 tests: private endpoints vs service endpoints, DNS integration,
// approval workflow, NSG support, network policies.
// ============================================================================

@description('Private DNS zone for Azure Blob Storage private endpoints. Uses environment() to derive the correct suffix for the target cloud (core.windows.net in public Azure).')
resource privateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2020-06-01' = if (deployPrivateEndpoint) {
  name: 'privatelink.blob.${az.environment().suffixes.storage}'
  location: 'global'
  tags: commonTags
}

@description('Link the blob private DNS zone to Spoke 1 VNet so resources can resolve storage-account.blob.core.windows.net to the private endpoint IP.')
resource privateDnsZoneBlobLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (deployPrivateEndpoint) {
  parent: privateDnsZoneBlob
  name: 'link-spoke1-blob'
  location: 'global'
  tags: commonTags
  properties: {
    virtualNetwork: { id: spoke1VNetId }
    registrationEnabled: false
  }
}

@description('''
Private endpoint for a storage account's blob service. Creates a network interface
in Spoke 1's data subnet with a private IP, then maps it to the storage account.
The privateLinkServiceConnections array specifies the target resource and sub-resource
(groupId). For Blob storage, the groupId is 'blob'.
''')
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = if (deployPrivateEndpoint && !empty(storageAccountResourceId)) {
  name: 'pe-az104-lab-storage'
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: spoke1DataSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'psc-az104-lab-storage'
        properties: {
          privateLinkServiceId: storageAccountResourceId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

@description('DNS zone group automatically registers the private endpoint private IP as an A record in the privatelink.blob.core.windows.net zone. This enables transparent FQDN resolution.')
resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (deployPrivateEndpoint && !empty(storageAccountResourceId)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-blob'
        properties: {
          privateDnsZoneId: privateDnsZoneBlob.id
        }
      }
    ]
  }
}

// ============================================================================
// AZURE BASTION
// ============================================================================
// Bastion provides secure RDP/SSH connectivity to VMs without exposing public
// IPs. It deploys into the AzureBastionSubnet (exact name required) and
// connects through the Azure portal or native client.
// AZ-104 tests: Bastion SKUs (Developer/Basic/Standard), subnet requirements
// (/26 minimum), NSG rules, and connectivity troubleshooting.
// ============================================================================

@description('Standard SKU static public IP for Azure Bastion. Bastion requires a Standard SKU public IP with static allocation.')
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) {
  name: 'pip-az104-lab-bastion'
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Using Basic SKU. Developer SKU is cheaper (~$0.05/hr vs ~$0.19/hr) but may
// not be available in all regions or deployable via Bicep. To save costs,
// check if Developer SKU is available in your region and switch via the portal.
@description('''
Azure Bastion provides browser-based and native-client RDP/SSH access to VMs
without requiring public IP addresses on the VMs. Basic SKU is used here;
Developer SKU is cheaper but has limited region availability via Bicep.
⚠️  Bastion Basic costs ~$0.19/hr (~$4.56/day). Deploy only when actively
needed for VM access, then delete to save costs.
''')
resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = if (deployBastion) {
  name: 'bastion-az104-lab'
  location: location
  tags: commonTags
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: { id: bastionPublicIp.id }
          subnet: { id: bastionSubnetId }
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the public DNS zone.')
output publicDnsZoneId string = publicDnsZone.id

@description('Azure-assigned name servers for the public DNS zone. Delegate your domain to these NS records to make it resolvable.')
output publicDnsZoneNameServers array = publicDnsZone.properties.nameServers

@description('Resource ID of the private DNS zone (az104-lab.internal).')
output privateDnsZoneId string = privateDnsZone.id

@description('Resource ID of the route table. Use this to verify effective routes on NICs in the associated subnet.')
output routeTableId string = routeTable.id

@description('Resource ID of the Azure Bastion host (empty string if not deployed).')
output bastionId string = deployBastion ? bastion.id : ''

@description('Resource ID of the storage private endpoint (empty string if not deployed).')
output privateEndpointId string = (deployPrivateEndpoint && !empty(storageAccountResourceId)) ? privateEndpoint.id : ''
