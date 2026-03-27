// ============================================================================
// Module 00: Foundation Setup
// AZ-104 Certification Lab — Infrastructure Scaffolding
// ============================================================================
// This module deploys the foundational networking infrastructure that all
// other AZ-104 lab modules depend on. It creates a hub virtual network
// with purpose-built subnets for Bastion, Gateway, Firewall, and management.
// ============================================================================

// --- Parameters ---

@description('Azure region for all resources. AZ-104 often tests knowledge of region pairs and availability.')
param location string = 'eastus'

@description('Environment tag applied to every resource. Useful for cost tracking and policy enforcement — both AZ-104 topics.')
param environment string = 'certlab'

@description('Deterministic unique suffix derived from the resource group ID. Ensures globally unique names without manual input.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// --- Variables ---

@description('Standard tags applied to every resource in this module for consistent governance.')
var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'foundation'
}

@description('Hub VNet name following the naming convention: {product}-{module}-{resource}.')
var hubVnetName = 'vnet-certlab-hub'

@description('Address space for the hub virtual network. A /16 gives 65,536 addresses — plenty of room for subnets.')
var hubAddressSpace = '10.0.0.0/16'

// --- Hub Virtual Network ---

@description('''
Hub virtual network for the AZ-104 lab. This is the central network that spoke VNets
will peer with in later modules. The hub-spoke topology is a core AZ-104 concept.

Subnets:
  - default (10.0.0.0/24)        : General-purpose workloads
  - AzureBastionSubnet (10.0.1.0/26) : Azure Bastion requires this exact name
  - GatewaySubnet (10.0.2.0/27)      : VPN/ExpressRoute gateway requires this exact name
  - AzureFirewallSubnet (10.0.3.0/26): Azure Firewall requires this exact name and at least /26
  - management (10.0.4.0/24)         : Management and monitoring workloads
''')
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: hubVnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        // Azure Bastion requires the subnet to be named exactly 'AzureBastionSubnet'.
        // Minimum size is /26 (64 addresses). Bastion provides secure RDP/SSH without public IPs.
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.1.0/26'
        }
      }
      {
        // VPN Gateway and ExpressRoute Gateway require a subnet named exactly 'GatewaySubnet'.
        // A /27 (32 addresses) is the minimum recommended size.
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.2.0/27'
        }
      }
      {
        // Azure Firewall requires a subnet named exactly 'AzureFirewallSubnet'.
        // Minimum size is /26 (64 addresses).
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.3.0/26'
        }
      }
      {
        name: 'management'
        properties: {
          addressPrefix: '10.0.4.0/24'
        }
      }
    ]
  }
}

// --- Outputs ---

@description('Resource ID of the hub virtual network. Other modules reference this to create peerings.')
output hubVnetId string = hubVnet.id

@description('Name of the hub virtual network.')
output hubVnetName string = hubVnet.name

@description('Resource ID of the default subnet.')
output defaultSubnetId string = hubVnet.properties.subnets[0].id

@description('Resource ID of the AzureBastionSubnet.')
output bastionSubnetId string = hubVnet.properties.subnets[1].id

@description('Resource ID of the GatewaySubnet.')
output gatewaySubnetId string = hubVnet.properties.subnets[2].id

@description('Resource ID of the AzureFirewallSubnet.')
output firewallSubnetId string = hubVnet.properties.subnets[3].id

@description('Resource ID of the management subnet.')
output managementSubnetId string = hubVnet.properties.subnets[4].id

@description('The unique suffix used for globally unique resource names. Pass this to downstream modules.')
output uniqueSuffix string = uniqueSuffix
