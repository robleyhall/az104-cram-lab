# Module 00: Foundation Setup

Infrastructure scaffolding for the AZ-104 certification lab. **Deploy this module first** — all other modules depend on the resources created here.

## What Gets Deployed

| Resource | Name | Purpose |
|----------|------|---------|
| Virtual Network | `vnet-certlab-hub` | Hub VNet for hub-spoke topology (10.0.0.0/16) |
| Subnet | `default` | General-purpose workloads (10.0.0.0/24) |
| Subnet | `AzureBastionSubnet` | Azure Bastion — secure RDP/SSH without public IPs (10.0.1.0/26) |
| Subnet | `GatewaySubnet` | VPN/ExpressRoute gateway (10.0.2.0/27) |
| Subnet | `AzureFirewallSubnet` | Azure Firewall (10.0.3.0/26) |
| Subnet | `management` | Management and monitoring workloads (10.0.4.0/24) |

All resources are tagged with `Environment=certlab`, `Project=az104-lab`, `Module=foundation`.

## Prerequisites

- An active Azure subscription
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with Azure CLI)

Verify your setup:

```bash
az --version
az bicep version
```

## Deploy

```bash
# 1. Create the resource group
az group create --name rg-certlab-foundation --location eastus

# 2. Preview changes (always do this first!)
az deployment group create \
  --resource-group rg-certlab-foundation \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --what-if

# 3. Deploy
az deployment group create \
  --resource-group rg-certlab-foundation \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Verify

```bash
# Confirm the VNet and subnets exist
az network vnet show \
  --resource-group rg-certlab-foundation \
  --name vnet-certlab-hub \
  --query '{name:name, addressSpace:addressSpace.addressPrefixes, subnets:subnets[].name}' \
  --output table

# List all subnets
az network vnet subnet list \
  --resource-group rg-certlab-foundation \
  --vnet-name vnet-certlab-hub \
  --output table
```

## Clean Up

```bash
az group delete --name rg-certlab-foundation --yes --no-wait
```

## AZ-104 Exam Relevance

This module covers concepts from several AZ-104 domains:

- **Configure and manage virtual networking** — VNet creation, address spaces, subnets
- **Hub-spoke topology** — centralised connectivity model
- **Special-purpose subnets** — Bastion, Gateway, and Firewall each require specific subnet names and minimum sizes
- **Resource tagging** — governance and cost management
- **Idempotent IaC** — deploying the same template repeatedly produces the same result
