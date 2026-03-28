// ──────────────────────────────────────────────────────────────────────────────
// Module 03 — Virtual Networking
// Deploys spoke VNets, VNet peering (spoke→hub), NSGs, ASGs, and a public IP.
// Covers AZ-104 domain: Configure and manage virtual networking (15–20%)
// ──────────────────────────────────────────────────────────────────────────────

// ─── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for all resources. Maps to AZ-104 skill: choose appropriate region for network resources.')
param location string = 'eastus'

@description('''Resource ID of the hub VNet deployed by Module 00 (rg-az104-lab-foundation).
Example: /subscriptions/{sub-id}/resourceGroups/rg-az104-lab-foundation/providers/Microsoft.Network/virtualNetworks/vnet-az104-lab-hub
Used for VNet peering — demonstrates cross-resource-group references.''')
param hubVNetResourceId string

@description('''Source IP address allowed for inbound SSH (port 22).
Set this to your public IP for least-privilege access. Default \'*\' allows any source (lab only).
AZ-104 skill: configure NSG rules with specific source/destination scoping.''')
param allowedSourceIP string = '*'

@description('Environment identifier used in resource tags for governance and cost tracking.')
param environment string = 'az104-lab'

// ─── Variables ───────────────────────────────────────────────────────────────

@description('Standard tags applied to every resource — enables cost allocation and governance.')
var tags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'networking'
}

@description('Hub VNet name parsed from the resource ID — used in peering resource naming.')
var hubVNetName = last(split(hubVNetResourceId, '/'))

// ─── Application Security Groups ─────────────────────────────────────────────
// ASGs let you group NICs logically and use those groups in NSG rules instead
// of IP addresses. AZ-104 skill: configure ASGs and use them in NSG rules.

@description('ASG for web-tier VMs — referenced as a source in the app-tier NSG rule.')
resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-01-01' = {
  name: 'asg-az104-lab-web'
  location: location
  tags: tags
}

@description('ASG for application-tier VMs.')
resource asgApp 'Microsoft.Network/applicationSecurityGroups@2024-01-01' = {
  name: 'asg-az104-lab-app'
  location: location
  tags: tags
}

@description('ASG for data-tier VMs — can be used in future NSG rules to restrict database access.')
resource asgData 'Microsoft.Network/applicationSecurityGroups@2024-01-01' = {
  name: 'asg-az104-lab-data'
  location: location
  tags: tags
}

// ─── Network Security Groups ─────────────────────────────────────────────────
// NSGs filter traffic at the subnet or NIC level. Rules are evaluated by
// priority (lowest number = highest priority). AZ-104 skill: create and
// configure NSGs, evaluate effective security rules.

@description('''NSG for the web tier (attached to spoke1/default subnet).
Rules: AllowHTTP (80), AllowHTTPS (443), AllowSSH (22, source-scoped), DenyAllInbound.
The explicit DenyAll at priority 4096 makes the deny visible in effective security rules.''')
resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-az104-lab-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          description: 'Allow inbound HTTP traffic from any source to port 80'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          description: 'Allow inbound HTTPS traffic from any source to port 443'
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowSSH'
        properties: {
          description: 'Allow inbound SSH from a specific IP — demonstrates source-scoped rules'
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: allowedSourceIP
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Explicit deny-all at low priority — overrides Azure defaults and makes deny visible in effective rules view'
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

@description('''NSG for the app tier (attached to spoke1/app subnet).
Uses an ASG as the source — only traffic originating from asg-az104-lab-web is allowed on port 8080.
Demonstrates ASG-based rules: a core AZ-104 concept.''')
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-az104-lab-app'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowFromWeb'
        properties: {
          description: 'Allow inbound on port 8080 only from NICs in the web ASG — demonstrates ASG source filtering'
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceApplicationSecurityGroups: [
            {
              id: asgWeb.id
            }
          ]
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Explicit deny-all inbound — ensures only AllowFromWeb traffic reaches the app tier'
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ─── Virtual Networks ────────────────────────────────────────────────────────
// Hub-spoke topology: Module 00 deployed the hub (10.0.0.0/16).
// This module deploys two spoke VNets peered to the hub.
// AZ-104 skills: create VNets, configure subnets, associate NSGs to subnets.

@description('''Spoke VNet 1 — primary workload network with three subnets.
- default (10.1.0.0/24): web tier, protected by nsg-az104-lab-web
- app     (10.1.1.0/24): app tier, protected by nsg-az104-lab-app
- data    (10.1.2.0/24): data tier, no NSG (add one as an exercise)
NSG-to-subnet association is configured inline — a common AZ-104 pattern.''')
resource vnetSpoke1 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-az104-lab-spoke1'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.1.0.0/24'
          networkSecurityGroup: {
            id: nsgWeb.id
          }
        }
      }
      {
        name: 'app'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: {
            id: nsgApp.id
          }
        }
      }
      {
        name: 'data'
        properties: {
          addressPrefix: '10.1.2.0/24'
        }
      }
    ]
  }
}

@description('''Spoke VNet 2 — secondary workload network with two subnets.
- default (10.2.0.0/24): general purpose
- app     (10.2.1.0/24): application workloads
No NSGs attached — available for exercises on NSG association.''')
resource vnetSpoke2 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-az104-lab-spoke2'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.2.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.2.0.0/24'
        }
      }
      {
        name: 'app'
        properties: {
          addressPrefix: '10.2.1.0/24'
        }
      }
    ]
  }
}

// ─── VNet Peering (spoke → hub) ──────────────────────────────────────────────
// Peering is non-transitive and must be created on BOTH sides.
// This template creates the spoke→hub direction only.
// The hub→spoke direction must be created separately in rg-az104-lab-foundation
// because the hub VNet lives in a different resource group.
// See README.md for the CLI commands to complete hub-side peering.
//
// AZ-104 skills: configure VNet peering, understand gateway transit,
// forwarded traffic, and non-transitive routing.

@description('''Peering from spoke1 → hub. Enables forwarded traffic so the hub can route
between spokes (requires a network virtual appliance or Azure Firewall in the hub).
useRemoteGateways is false — set to true if a VPN/ExpressRoute gateway exists in the hub.''')
resource peeringSpoke1ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: vnetSpoke1
  name: 'peer-spoke1-to-${hubVNetName}'
  properties: {
    remoteVirtualNetwork: {
      id: hubVNetResourceId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

@description('Peering from spoke2 → hub. Same configuration as spoke1 peering.')
resource peeringSpoke2ToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = {
  parent: vnetSpoke2
  name: 'peer-spoke2-to-${hubVNetName}'
  properties: {
    remoteVirtualNetwork: {
      id: hubVNetResourceId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// ─── Public IP Address ───────────────────────────────────────────────────────
// Standard SKU + Static allocation is the recommended combination.
// Basic SKU is being retired — AZ-104 tests Standard SKU knowledge.

@description('''Standard static public IP for web-tier workloads.
Standard SKU is zone-redundant by default and required for Standard Load Balancer.
AZ-104 skill: create and configure public IP addresses, understand SKU differences.''')
resource pipWeb 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-az104-lab-web'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ─── Outputs ─────────────────────────────────────────────────────────────────

@description('Resource ID of spoke VNet 1 — used by downstream modules (compute, load balancing).')
output spoke1VNetId string = vnetSpoke1.id

@description('Name of spoke VNet 1.')
output spoke1VNetName string = vnetSpoke1.name

@description('Resource ID of spoke VNet 2.')
output spoke2VNetId string = vnetSpoke2.id

@description('Name of spoke VNet 2.')
output spoke2VNetName string = vnetSpoke2.name

@description('Resource ID of the web-tier NSG.')
output nsgWebId string = nsgWeb.id

@description('Resource ID of the app-tier NSG.')
output nsgAppId string = nsgApp.id

@description('Resource ID of the web-tier ASG — attach to VM NICs to apply ASG-based NSG rules.')
output asgWebId string = asgWeb.id

@description('Resource ID of the app-tier ASG.')
output asgAppId string = asgApp.id

@description('Resource ID of the data-tier ASG.')
output asgDataId string = asgData.id

@description('Allocated static public IP address for the web tier.')
output publicIPAddress string = pipWeb.properties.ipAddress

@description('Resource ID of the public IP — used when associating with a NIC or load balancer.')
output publicIPId string = pipWeb.id
