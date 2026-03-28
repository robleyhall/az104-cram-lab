# Module 04: DNS & Connectivity

Azure DNS, Private DNS, User-Defined Routes, Service Endpoints, Private Endpoints, and Azure Bastion — covering the connectivity and name-resolution topics in the **Implement and manage virtual networking** domain (15–20% of AZ-104).

## Learning Objectives

After completing this module you will be able to:

| Skill | AZ-104 Exam Objective |
|-------|----------------------|
| Create and configure Azure DNS zones and records | Configure Azure DNS |
| Configure Private DNS zones with VNet links and auto-registration | Configure Azure DNS |
| Create route tables and UDRs to control traffic flow | Configure and manage virtual networking |
| Enable service endpoints on subnets for PaaS connectivity | Implement and manage virtual networking |
| Deploy private endpoints with Private Link and DNS integration | Implement and manage virtual networking |
| Deploy Azure Bastion for secure VM access without public IPs | Monitor and troubleshoot virtual networking |
| Troubleshoot name resolution and connectivity issues | Monitor and troubleshoot virtual networking |

## Savill's AZ-104 Cram — Video Timestamps

These timestamps map to [John Savill's AZ-104 Cram v2](https://www.youtube.com/watch?v=0Knf9nub4-k):

| Topic | Timestamp | Link |
|-------|-----------|------|
| Azure DNS | 1:38:41 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5921s) |
| Private DNS | 1:41:35 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6095s) |
| Connectivity | 1:46:51 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6411s) |
| S2S VPN | 1:47:52 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6472s) |
| ExpressRoute | 1:50:34 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6634s) |
| Virtual WAN | 1:56:09 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=6969s) |
| UDRs | 1:58:36 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7116s) |
| Service Endpoints | 1:59:55 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7195s) |
| Private Endpoints | 2:04:50 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7490s) |
| Bastion | 2:08:03 | [▶ Watch](https://www.youtube.com/watch?v=0Knf9nub4-k&t=7683s) |

> **Conceptual only (not deployed in this lab):** S2S VPN, ExpressRoute, and Virtual WAN are covered in the cram video but are too expensive and complex for a study lab. Know the concepts, SKUs, and use cases for the exam.

## What Gets Deployed

| Resource | Name | Purpose |
|----------|------|---------|
| Public DNS Zone | `az104-lab.example.com` | Azure DNS with A, CNAME, TXT records |
| Private DNS Zone | `az104-lab.internal` | Internal name resolution across VNets |
| Private DNS VNet Link | `link-hub` | Hub VNet link (auto-registration enabled) |
| Private DNS VNet Link | `link-spoke1` | Spoke 1 VNet link (auto-registration disabled) |
| Route Table | `rt-az104-lab-spoke1` | UDR forcing internet traffic → NVA (10.0.3.4) |
| Service Endpoint | Microsoft.Storage | On spoke1/data subnet for storage access |
| Private DNS Zone | `privatelink.blob.core.windows.net` | DNS for storage private endpoint *(conditional)* |
| Private Endpoint | `pe-az104-lab-storage` | Private connectivity to storage blob *(conditional)* |
| Public IP | `pip-az104-lab-bastion` | Standard SKU static IP for Bastion *(conditional)* |
| Azure Bastion | `bastion-az104-lab` | Secure RDP/SSH without VM public IPs *(conditional)* |

All resources tagged: `Environment=az104-lab`, `Project=az104-lab`, `Module=dns-connectivity`.

## Prerequisites

- **Module 00** (Foundation) deployed → provides hub VNet and AzureBastionSubnet
- **Module 03** (Networking) deployed → provides spoke VNets and subnets
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) v2.60+
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with Azure CLI)

Verify your setup:

```bash
az --version
az bicep version
```

Collect outputs from prerequisite modules:

```bash
# Hub VNet ID (from Module 00)
HUB_VNET_ID=$(az deployment group show \
  --resource-group rg-az104-lab-foundation \
  --name main \
  --query properties.outputs.hubVnetId.value -o tsv)

# Spoke 1 VNet ID (from Module 03)
SPOKE1_VNET_ID=$(az deployment group show \
  --resource-group rg-az104-lab-networking \
  --name main \
  --query properties.outputs.spoke1VnetId.value -o tsv)

# Spoke 1 Data Subnet ID (from Module 03)
SPOKE1_DATA_SUBNET_ID=$(az deployment group show \
  --resource-group rg-az104-lab-networking \
  --name main \
  --query properties.outputs.spoke1DataSubnetId.value -o tsv)
```

## Deploy

> ⚠️ **This module deploys into `rg-az104-lab-networking`** (same RG as Module 03) because it modifies existing spoke subnets with route table and service endpoint associations.

```bash
# 1. Preview changes (always do this first!)
az deployment group create \
  --resource-group rg-az104-lab-networking \
  --template-file main.bicep \
  --parameters \
    hubVNetId="$HUB_VNET_ID" \
    spoke1VNetId="$SPOKE1_VNET_ID" \
    spoke1DataSubnetId="$SPOKE1_DATA_SUBNET_ID" \
    deployBastion=false \
  --what-if

# 2. Deploy (without Bastion to save costs)
az deployment group create \
  --resource-group rg-az104-lab-networking \
  --template-file main.bicep \
  --parameters \
    hubVNetId="$HUB_VNET_ID" \
    spoke1VNetId="$SPOKE1_VNET_ID" \
    spoke1DataSubnetId="$SPOKE1_DATA_SUBNET_ID" \
    deployBastion=false

# 3. Deploy Bastion only when you need VM access
az deployment group create \
  --resource-group rg-az104-lab-networking \
  --template-file main.bicep \
  --parameters \
    hubVNetId="$HUB_VNET_ID" \
    spoke1VNetId="$SPOKE1_VNET_ID" \
    spoke1DataSubnetId="$SPOKE1_DATA_SUBNET_ID" \
    deployBastion=true
```

### Deploy Private Endpoint (after Module 06)

```bash
STORAGE_ID=$(az deployment group show \
  --resource-group rg-az104-lab-storage \
  --name main \
  --query properties.outputs.storageAccountId.value -o tsv)

az deployment group create \
  --resource-group rg-az104-lab-networking \
  --template-file main.bicep \
  --parameters \
    hubVNetId="$HUB_VNET_ID" \
    spoke1VNetId="$SPOKE1_VNET_ID" \
    spoke1DataSubnetId="$SPOKE1_DATA_SUBNET_ID" \
    deployPrivateEndpoint=true \
    storageAccountResourceId="$STORAGE_ID"
```

## Verify

```bash
# --- Public DNS Zone ---
az network dns zone show \
  --resource-group rg-az104-lab-networking \
  --name az104-lab.example.com \
  --query '{name:name, nameServers:nameServers}' -o json

az network dns record-set list \
  --resource-group rg-az104-lab-networking \
  --zone-name az104-lab.example.com \
  --output table

# --- Private DNS Zone ---
az network private-dns zone show \
  --resource-group rg-az104-lab-networking \
  --name az104-lab.internal \
  --output table

az network private-dns link vnet list \
  --resource-group rg-az104-lab-networking \
  --zone-name az104-lab.internal \
  --output table

az network private-dns record-set a list \
  --resource-group rg-az104-lab-networking \
  --zone-name az104-lab.internal \
  --output table

# --- Route Table & Effective Routes ---
az network route-table show \
  --resource-group rg-az104-lab-networking \
  --name rt-az104-lab-spoke1 \
  --query '{name:name, routes:routes[].{name:name, prefix:addressPrefix, nextHop:nextHopType, nextHopIp:nextHopIpAddress}}' \
  -o json

# Check effective routes on a NIC in the spoke1/default subnet
# az network nic show-effective-route-table -g rg-az104-lab-networking -n <nic-name> -o table

# --- Service Endpoint ---
az network vnet subnet show \
  --resource-group rg-az104-lab-networking \
  --vnet-name vnet-az104-lab-spoke1 \
  --name data \
  --query '{name:name, serviceEndpoints:serviceEndpoints[].service}' -o json

# --- Bastion ---
az network bastion list \
  --resource-group rg-az104-lab-networking \
  --output table

# --- Private Endpoint (if deployed) ---
az network private-endpoint list \
  --resource-group rg-az104-lab-networking \
  --output table
```

## Cost Warning

| Resource | Cost | Notes |
|----------|------|-------|
| **Azure Bastion (Basic)** | **~$0.19/hr (~$4.56/day)** | Deploy only when needed for VM access |
| DNS Zones | ~$0.50/month per zone | Minimal cost, safe to leave deployed |
| Route Table | Free | No cost for the resource itself |
| Private Endpoint | ~$0.01/hr | Minimal cost |
| Service Endpoint | Free | No cost — it's a subnet configuration |

> 💡 **Cost tip:** Set `deployBastion=false` for normal study sessions. Only deploy Bastion when you need to RDP/SSH into VMs, then delete it immediately after.

## Key Concepts for the Exam

### Azure DNS vs Private DNS

| Feature | Azure DNS (Public) | Azure Private DNS |
|---------|-------------------|-------------------|
| Resolution | Public internet | Within linked VNets only |
| Zone location | Global | Global |
| Auto-registration | No | Yes (via VNet link) |
| Record types | A, AAAA, CNAME, MX, TXT, SRV, NS, SOA | A, AAAA, CNAME, MX, TXT, SRV, SOA |
| Alias records | Yes (point to Azure resources) | No |

### Service Endpoints vs Private Endpoints

| Feature | Service Endpoint | Private Endpoint |
|---------|-----------------|-----------------|
| IP used | Service public IP (optimised route) | Private IP from your VNet |
| DNS | No change | Requires private DNS zone |
| Data exfiltration protection | No | Yes |
| Cross-region | Yes | Yes |
| Cost | Free | ~$0.01/hr |
| NSG support | Via service tags | Yes (network policies) |
| On-premises access | No (VNet only) | Yes (via VPN/ExpressRoute) |

### UDR Next Hop Types

| Next Hop Type | Use Case |
|---------------|----------|
| VirtualAppliance | Force traffic through NVA/firewall (IP address required) |
| VirtualNetworkGateway | Route to on-premises via VPN/ExpressRoute |
| VirtualNetwork | Override default VNet routing |
| Internet | Force traffic directly to internet |
| None | Drop traffic (blackhole route) |

### Bastion SKUs

| Feature | Developer | Basic | Standard |
|---------|-----------|-------|----------|
| Cost | ~$0.05/hr | ~$0.19/hr | ~$0.53/hr |
| Concurrent sessions | 1 | 25 | 50 |
| Native client | No | No | Yes |
| File transfer | No | No | Yes |
| IP-based connection | No | No | Yes |

## Conceptual Topics (Not Deployed)

These topics appear on the AZ-104 exam but are too expensive or complex for a study lab:

- **Site-to-Site VPN** — connects on-premises to Azure via IPsec/IKE tunnel. Requires a VPN Gateway (~$0.04/hr minimum) and an on-premises VPN device.
- **ExpressRoute** — private, dedicated connection from on-premises to Azure via a connectivity provider. Enterprise-grade, not practical for study labs.
- **Virtual WAN** — managed hub-and-spoke service that simplifies large-scale branch connectivity. Know the difference between Basic and Standard SKUs.

Watch the cram video sections linked above to cover these conceptually.

## Clean Up

```bash
# Delete Bastion first (highest cost)
az network bastion delete \
  --resource-group rg-az104-lab-networking \
  --name bastion-az104-lab \
  --no-wait

az network public-ip delete \
  --resource-group rg-az104-lab-networking \
  --name pip-az104-lab-bastion

# Delete private endpoint (if deployed)
az network private-endpoint delete \
  --resource-group rg-az104-lab-networking \
  --name pe-az104-lab-storage

# Delete DNS zones
az network dns zone delete \
  --resource-group rg-az104-lab-networking \
  --name az104-lab.example.com --yes

az network private-dns zone delete \
  --resource-group rg-az104-lab-networking \
  --name az104-lab.internal --yes

az network private-dns zone delete \
  --resource-group rg-az104-lab-networking \
  --name privatelink.blob.core.windows.net --yes

# Delete route table
az network route-table delete \
  --resource-group rg-az104-lab-networking \
  --name rt-az104-lab-spoke1

# Or delete everything by redeploying Module 03 without Module 04 resources
```

## AZ-104 Exam Relevance

This module covers concepts from the **Implement and manage virtual networking** domain:

- **Configure Azure DNS** — public zones, record types, TTL, alias records, delegation
- **Configure Private DNS** — private zones, VNet links, auto-registration, split-horizon
- **Configure UDRs** — route tables, next hop types, effective routes, BGP propagation
- **Service endpoints** — subnet-level PaaS connectivity, firewall rules integration
- **Private endpoints** — Private Link, DNS zone groups, approval workflow, network policies
- **Azure Bastion** — secure VM access, SKU selection, subnet requirements
- **Troubleshoot connectivity** — effective routes, DNS resolution, NSG flow logs
