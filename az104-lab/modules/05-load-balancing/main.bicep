// ============================================================================
// Module 05: Load Balancing
// AZ-104 Certification Lab — Azure Load Balancer & Traffic Manager
// ============================================================================
// This module deploys load-balancing resources that cover 15–20 % of the
// AZ-104 exam. It creates a Standard public Azure Load Balancer with health
// probes, LB rules, and inbound NAT rules, plus a Traffic Manager profile
// for DNS-based global routing.
//
// NOTE: Azure Application Gateway (~$0.25/hr+) and Azure Front Door are
//       intentionally omitted from the Bicep to avoid runaway lab costs.
//       Conceptual notes and exam-relevant details live in the README.
// ============================================================================

// --- Parameters ---

@description('Azure region for all resources. Standard Load Balancer is regional; Traffic Manager is global but needs a location for the profile metadata.')
param location string = 'eastus'

@description('Resource ID of a spoke subnet whose VMs will join the backend pool. Passed in from Module 03 outputs. Not consumed directly by the LB resource but referenced by NIC configs in Module 07.')
param spoke1SubnetId string = ''

@description('Environment label applied to every resource. Useful for cost tracking and Azure Policy — both AZ-104 topics.')
param environment string = 'certlab'

@description('Deterministic unique suffix derived from the resource group ID. Ensures globally unique names (e.g. Traffic Manager DNS) without manual input.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// --- Variables ---

@description('Standard tags applied to every resource in this module for consistent governance.')
var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'load-balancing'
}

@description('Name of the public IP attached to the Load Balancer frontend.')
var lbPublicIpName = 'pip-${environment}-lb'

@description('Name of the Standard public Load Balancer.')
var lbName = 'lb-${environment}-web'

@description('Name of the Traffic Manager profile.')
var tmProfileName = 'tm-${environment}-web'

@description('Globally unique DNS label for the Traffic Manager profile. Must be unique across all of Azure.')
var tmDnsName = '${environment}-tm-${uniqueSuffix}'

// --- Public IP for Load Balancer ---

@description('''
Standard SKU public IP for the Load Balancer frontend.
AZ-104 key point: Standard SKU public IPs are zone-redundant by default and
require an associated NSG on the backend NICs (Basic SKU does not).
Standard public IPs are static-only; Basic can be dynamic or static.
''')
resource lbPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: lbPublicIpName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// --- Public Load Balancer (Standard SKU) ---

@description('''
Standard public Azure Load Balancer.

AZ-104 exam topics covered:
  • Layer 4 (TCP/UDP) load balancing — does NOT inspect HTTP headers
  • Frontend IP configurations (public or internal)
  • Backend address pools — VMs or VMSS instances
  • Health probes — HTTP, HTTPS, or TCP; unhealthy threshold removes instance
  • Load-balancing rules — map frontend port to backend port
  • Inbound NAT rules — port-forward to a specific VM (e.g. SSH 50001 → 22)
  • Session persistence — None (5-tuple), Client IP, Client IP + Protocol
  • Standard SKU is zone-aware; Basic SKU is NOT
  • Standard SKU backend pool members MUST have an NSG on their NIC/subnet
  • Floating IP (Direct Server Return) — used for SQL AlwaysOn / HA scenarios
''')
resource loadBalancer 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: lbName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'fe-web'
        properties: {
          publicIPAddress: {
            id: lbPublicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bp-${environment}-web'
      }
    ]
    probes: [
      {
        // Health probe determines if a backend instance can receive traffic.
        // If an instance fails the unhealthy threshold, the LB stops sending new connections.
        name: 'hp-http'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 15
          numberOfProbes: 2 // Unhealthy threshold — instance removed after 2 consecutive failures
          probeThreshold: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        // Distributes inbound traffic arriving on frontend port 80 across all
        // healthy backend pool members on port 80.
        name: 'rule-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-web')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bp-${environment}-web')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'hp-http')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default' // 5-tuple hash (None) — no session persistence
          enableTcpReset: true        // Standard SKU feature — sends TCP RST on idle timeout
          disableOutboundSnat: false
        }
      }
    ]
    inboundNatRules: [
      {
        // Inbound NAT rules forward traffic from a specific frontend port to a
        // specific backend VM port. Useful for SSH/RDP to individual VMs behind the LB.
        // AZ-104 tip: NAT rules target a single VM; LB rules target a pool.
        name: 'natrule-ssh-vm1'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-web')
          }
          protocol: 'Tcp'
          frontendPort: 50001
          backendPort: 22
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          enableTcpReset: true
        }
      }
      {
        name: 'natrule-ssh-vm2'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'fe-web')
          }
          protocol: 'Tcp'
          frontendPort: 50002
          backendPort: 22
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          enableTcpReset: true
        }
      }
    ]
  }
}

// --- Traffic Manager Profile ---

@description('''
Traffic Manager profile with Performance routing.

AZ-104 exam topics covered:
  • DNS-based global traffic distribution — works at the DNS layer, NOT inline with data
  • Routing methods:
      - Priority    — active/passive failover
      - Weighted    — distribute by weight (e.g. 70/30 canary)
      - Performance — route to the closest (lowest latency) endpoint
      - Geographic  — route based on user's geographic origin
      - MultiValue  — returns multiple healthy endpoints in a single DNS response
      - Subnet      — map client IP ranges to specific endpoints
  • Endpoint types: Azure, External, Nested
  • Health monitoring — Traffic Manager probes endpoints and removes unhealthy ones from DNS
  • TTL affects failover speed vs. DNS query volume trade-off
  • Traffic Manager returns a CNAME; the client resolves and connects directly to the endpoint
''')
resource trafficManager 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: tmProfileName
  location: 'global' // Traffic Manager is always global
  tags: commonTags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: tmDnsName
      ttl: 60 // Low TTL for lab — faster failover; production would use 300+
    }
    monitorConfig: {
      protocol: 'HTTP'
      port: 80
      path: '/'
      intervalInSeconds: 30
      timeoutInSeconds: 10
      toleratedNumberOfFailures: 3
    }
  }
}

// --- Traffic Manager Endpoints (commented out) ---
// Endpoints require deployed targets (VMs, App Service, Public IPs).
// Uncomment and configure after Module 07 (Compute) is deployed.

// @description('Azure endpoint pointing to the Load Balancer public IP in the primary region.')
// resource tmEndpointPrimary 'Microsoft.Network/trafficmanagerprofiles/azureEndpoints@2022-04-01' = {
//   parent: trafficManager
//   name: 'ep-primary'
//   properties: {
//     targetResourceId: lbPublicIp.id   // Public IP of the LB
//     endpointStatus: 'Enabled'
//     weight: 100
//     priority: 1
//   }
// }

// @description('External endpoint pointing to an on-prem or third-party service.')
// resource tmEndpointExternal 'Microsoft.Network/trafficmanagerprofiles/externalEndpoints@2022-04-01' = {
//   parent: trafficManager
//   name: 'ep-external'
//   properties: {
//     target: 'contoso.example.com'
//     endpointStatus: 'Enabled'
//     weight: 50
//     priority: 2
//   }
// }

// --- Outputs ---

@description('Resource ID of the Load Balancer. Used by NIC configurations in Module 07.')
output loadBalancerId string = loadBalancer.id

@description('Name of the Load Balancer.')
output loadBalancerName string = loadBalancer.name

@description('Resource ID of the backend address pool. Attach VM NICs to this pool in Module 07.')
output backendPoolId string = loadBalancer.properties.backendAddressPools[0].id

@description('Name of the backend address pool.')
output backendPoolName string = loadBalancer.properties.backendAddressPools[0].name

@description('Resource ID of the first inbound NAT rule (SSH-VM1, port 50001 → 22).')
output natRuleSshVm1Id string = loadBalancer.properties.inboundNatRules[0].id

@description('Resource ID of the second inbound NAT rule (SSH-VM2, port 50002 → 22).')
output natRuleSshVm2Id string = loadBalancer.properties.inboundNatRules[1].id

@description('Public IP address of the Load Balancer frontend.')
output lbPublicIpAddress string = lbPublicIp.properties.ipAddress

@description('FQDN of the Traffic Manager profile. Clients resolve this CNAME to reach the nearest healthy endpoint.')
output trafficManagerFqdn string = trafficManager.properties.dnsConfig.fqdn

@description('Resource ID of the Traffic Manager profile.')
output trafficManagerId string = trafficManager.id

@description('The spoke1SubnetId passed through for downstream reference.')
output spoke1SubnetIdOut string = spoke1SubnetId
