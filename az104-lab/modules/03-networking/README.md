# Module 03 — Virtual Networking

Deploys a hub-spoke network topology with NSGs, ASGs, and a public IP. Covers the AZ-104 exam domain **Configure and manage virtual networking (15–20%)**.

## Learning Objectives

After deploying this module you will be able to:

| AZ-104 Skill | What You'll Practice |
|---|---|
| Create and configure VNets and subnets | Deploy two spoke VNets with multiple subnets and non-overlapping address spaces |
| Configure VNet peering | Establish spoke→hub peering with forwarded traffic and gateway transit options |
| Configure public IP addresses | Create a Standard SKU static public IP (Basic SKU is being retired) |
| Create and configure NSGs | Build web and app tier NSGs with prioritized allow/deny rules |
| Create and configure ASGs | Group resources by role (web, app, data) and use ASGs as rule sources |
| Evaluate effective security rules | Inspect merged NSG rules on a subnet using Azure CLI |

## Architecture

```
                    ┌──────────────────────┐
                    │   vnet-certlab-hub   │
                    │     10.0.0.0/16      │
                    │   (Module 00)        │
                    └──────┬───────┬───────┘
                  peering  │       │  peering
              ┌────────────┘       └────────────┐
              ▼                                  ▼
┌─────────────────────────┐        ┌─────────────────────────┐
│  vnet-certlab-spoke1    │        │  vnet-certlab-spoke2    │
│    10.1.0.0/16          │        │    10.2.0.0/16          │
│                         │        │                         │
│  ┌─────────────────┐   │        │  ┌─────────────────┐   │
│  │ default /24      │   │        │  │ default /24      │   │
│  │ + nsg-web        │   │        │  └─────────────────┘   │
│  └─────────────────┘   │        │  ┌─────────────────┐   │
│  ┌─────────────────┐   │        │  │ app /24          │   │
│  │ app /24          │   │        │  └─────────────────┘   │
│  │ + nsg-app        │   │        └─────────────────────────┘
│  └─────────────────┘   │
│  ┌─────────────────┐   │        ASGs: asg-web, asg-app, asg-data
│  │ data /24         │   │        Public IP: pip-certlab-web (Standard/Static)
│  └─────────────────┘   │
└─────────────────────────┘
```

**Hub-spoke topology** is the recommended Azure network architecture. The hub VNet (Module 00) hosts shared services like Azure Bastion, VPN Gateway, and Azure Firewall. Spoke VNets connect to the hub via peering and host workloads. Peering is **non-transitive** — spoke-to-spoke traffic must route through a network virtual appliance (NVA) or Azure Firewall in the hub.

## What Gets Deployed

| Resource | Name | Details |
|---|---|---|
| Virtual Network | `vnet-certlab-spoke1` | 10.1.0.0/16 — subnets: default, app, data |
| Virtual Network | `vnet-certlab-spoke2` | 10.2.0.0/16 — subnets: default, app |
| VNet Peering | `peer-spoke1-to-vnet-certlab-hub` | spoke1 → hub (forwarded traffic enabled) |
| VNet Peering | `peer-spoke2-to-vnet-certlab-hub` | spoke2 → hub (forwarded traffic enabled) |
| Network Security Group | `nsg-certlab-web` | HTTP 80, HTTPS 443, SSH 22, DenyAll |
| Network Security Group | `nsg-certlab-app` | Allow 8080 from asg-web only, DenyAll |
| Application Security Group | `asg-certlab-web` | Web-tier NIC grouping |
| Application Security Group | `asg-certlab-app` | App-tier NIC grouping |
| Application Security Group | `asg-certlab-data` | Data-tier NIC grouping |
| Public IP Address | `pip-certlab-web` | Standard SKU, Static allocation |

## Cram Session Timestamps

These timestamps reference [John Savill's AZ-104 Cram](https://www.youtube.com/watch?v=0Knf9nub4-k) video:

| Topic | Timestamp | Link |
|---|---|---|
| Networking Overview | 1:09:28 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4168s) |
| Virtual Networks | 1:10:15 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4215s) |
| VNet Peering | 1:20:00 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4800s) |
| Network Virtual Appliances (NVA) | 1:24:36 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5076s) |
| Network Security Groups | 1:28:47 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5327s) |
| Azure Firewall | 1:36:27 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=5787s) |

## Prerequisites

- **Azure CLI** v2.60+ with Bicep CLI installed (`az bicep version`)
- **Module 00 deployed** — the hub VNet (`vnet-certlab-hub`) must exist in `rg-certlab-foundation`
- Know your **public IP** for the SSH rule (run `curl -s ifconfig.me`)

## Deploy

### 1. Get the hub VNet resource ID

```bash
HUB_VNET_ID=$(az network vnet show \
  --resource-group rg-certlab-foundation \
  --name vnet-certlab-hub \
  --query id -o tsv)

echo "Hub VNet ID: $HUB_VNET_ID"
```

### 2. Create the resource group

```bash
az group create \
  --name rg-certlab-networking \
  --location eastus \
  --tags Environment=certlab Project=az104-lab Module=networking
```

### 3. Preview changes

```bash
az deployment group what-if \
  --resource-group rg-certlab-networking \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters hubVNetResourceId="$HUB_VNET_ID"
```

### 4. Deploy

```bash
az deployment group create \
  --resource-group rg-certlab-networking \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters hubVNetResourceId="$HUB_VNET_ID"
```

> **Tip:** To restrict SSH access, pass your IP:
> ```bash
> MY_IP=$(curl -s ifconfig.me)
> az deployment group create \
>   --resource-group rg-certlab-networking \
>   --template-file main.bicep \
>   --parameters main.bicepparam \
>   --parameters hubVNetResourceId="$HUB_VNET_ID" allowedSourceIP="$MY_IP"
> ```

### 5. Create hub-side peering

The template creates spoke→hub peering. You must also create hub→spoke peering in the hub's resource group:

```bash
# Hub → Spoke1
az network vnet peering create \
  --resource-group rg-certlab-foundation \
  --name peer-hub-to-spoke1 \
  --vnet-name vnet-certlab-hub \
  --remote-vnet "$( az network vnet show -g rg-certlab-networking -n vnet-certlab-spoke1 --query id -o tsv )" \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --allow-gateway-transit

# Hub → Spoke2
az network vnet peering create \
  --resource-group rg-certlab-foundation \
  --name peer-hub-to-spoke2 \
  --vnet-name vnet-certlab-hub \
  --remote-vnet "$( az network vnet show -g rg-certlab-networking -n vnet-certlab-spoke2 --query id -o tsv )" \
  --allow-vnet-access \
  --allow-forwarded-traffic \
  --allow-gateway-transit
```

## Verify

### VNets and subnets

```bash
# List VNets in the resource group
az network vnet list \
  --resource-group rg-certlab-networking \
  --query '[].{Name:name, AddressSpace:addressSpace.addressPrefixes[0]}' \
  -o table

# Show spoke1 subnets
az network vnet subnet list \
  --resource-group rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 \
  --query '[].{Name:name, Prefix:addressPrefix, NSG:networkSecurityGroup.id}' \
  -o table
```

### VNet peering status

```bash
# Check peering state (should be "Connected" on both sides)
az network vnet peering list \
  --resource-group rg-certlab-networking \
  --vnet-name vnet-certlab-spoke1 \
  --query '[].{Name:name, State:peeringState, Forwarding:allowForwardedTraffic}' \
  -o table

az network vnet peering list \
  --resource-group rg-certlab-networking \
  --vnet-name vnet-certlab-spoke2 \
  --query '[].{Name:name, State:peeringState, Forwarding:allowForwardedTraffic}' \
  -o table
```

### NSG rules

```bash
# List web NSG rules
az network nsg rule list \
  --resource-group rg-certlab-networking \
  --nsg-name nsg-certlab-web \
  --query '[].{Name:name, Priority:priority, Access:access, Port:destinationPortRange, Source:sourceAddressPrefix}' \
  -o table

# List app NSG rules (note the ASG-based source)
az network nsg rule list \
  --resource-group rg-certlab-networking \
  --nsg-name nsg-certlab-app \
  -o table
```

### Effective security rules

Once a VM is deployed in a subnet, check its effective NSG rules (AZ-104 exam topic):

```bash
# Replace with an actual NIC name after deploying a VM in Module 07
az network nic list-effective-nsg \
  --resource-group rg-certlab-networking \
  --name <nic-name> \
  -o table
```

### Public IP

```bash
az network public-ip show \
  --resource-group rg-certlab-networking \
  --name pip-certlab-web \
  --query '{Name:name, IP:ipAddress, SKU:sku.name, Method:publicIPAllocationMethod}' \
  -o table
```

### ASGs

```bash
az network asg list \
  --resource-group rg-certlab-networking \
  --query '[].{Name:name, Location:location}' \
  -o table
```

## Clean Up

```bash
# Remove hub-side peerings first
az network vnet peering delete \
  --resource-group rg-certlab-foundation \
  --vnet-name vnet-certlab-hub \
  --name peer-hub-to-spoke1

az network vnet peering delete \
  --resource-group rg-certlab-foundation \
  --vnet-name vnet-certlab-hub \
  --name peer-hub-to-spoke2

# Delete the networking resource group
az group delete --name rg-certlab-networking --yes --no-wait
```

## AZ-104 Exam Relevance

This module maps to the exam domain **Configure and manage virtual networking (15–20%)**:

- **Configure virtual networks** — VNet creation, address spaces, subnet design
- **Configure VNet peering** — hub-spoke topology, peering state, gateway transit vs. forwarded traffic
- **Configure public IP addresses** — Standard vs. Basic SKU, static vs. dynamic allocation
- **Configure NSGs** — rule priority, direction, protocol, port, source/destination scoping
- **Configure ASGs** — logical NIC grouping, ASG-based NSG rules (no IP addresses needed)
- **Evaluate effective security rules** — merged view of NSG rules applied to a NIC (subnet + NIC level)

### Key Exam Tips

1. **Peering is non-transitive** — Spoke1 cannot reach Spoke2 through the hub without an NVA or Azure Firewall.
2. **NSG rules** — Lowest priority number wins. Default rules (65000+) cannot be deleted but can be overridden.
3. **ASGs** — All NICs in an ASG must be in the same VNet. ASGs simplify rules by replacing IP addresses.
4. **Public IP SKUs** — Standard SKU is zone-redundant, closed to inbound by default (needs NSG allow), and required for Standard Load Balancer.
5. **Address spaces** — VNets being peered must **not** have overlapping address ranges.
