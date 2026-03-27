# Architecture Overview

This document describes the architecture of the AZ-104 CertForge Lab environment.

---

## Hub-Spoke Network Topology

The lab uses a **hub-spoke topology**, the most common enterprise Azure network pattern and a key concept for the AZ-104 exam.

```
                    ┌──────────────────────┐
                    │     Hub VNet         │
                    │    10.0.0.0/16       │
                    │                      │
                    │  ┌────────────────┐  │
                    │  │ AzureBastionSub│  │       ┌──────────────┐
                    │  │ 10.0.0.0/26   │──│──────►│   Internet   │
                    │  └────────────────┘  │       └──────────────┘
                    │  ┌────────────────┐  │
                    │  │ GatewaySubnet  │  │
                    │  │ 10.0.1.0/27   │  │
                    │  └────────────────┘  │
                    │  ┌────────────────┐  │
                    │  │ SharedServices │  │
                    │  │ 10.0.2.0/24   │  │
                    │  └────────────────┘  │
                    │  ┌────────────────┐  │
                    │  │ AzFirewallSub  │  │
                    │  │ 10.0.3.0/26   │  │
                    │  └────────────────┘  │
                    └──────────┬───────────┘
                               │
                    VNet Peering│
               ┌───────────────┼───────────────┐
               │                               │
    ┌──────────▼──────────┐         ┌──────────▼──────────┐
    │   Spoke 1 VNet      │         │   Spoke 2 VNet      │
    │   10.1.0.0/16       │         │   10.2.0.0/16       │
    │                     │         │                     │
    │ ┌─────────────────┐ │         │ ┌─────────────────┐ │
    │ │ Workload Subnet │ │         │ │ Workload Subnet │ │
    │ │ 10.1.1.0/24     │ │         │ │ 10.2.1.0/24     │ │
    │ └─────────────────┘ │         │ └─────────────────┘ │
    │ ┌─────────────────┐ │         │ ┌─────────────────┐ │
    │ │ App Subnet      │ │         │ │ Data Subnet     │ │
    │ │ 10.1.2.0/24     │ │         │ │ 10.2.2.0/24     │ │
    │ └─────────────────┘ │         │ └─────────────────┘ │
    │ ┌─────────────────┐ │         │ ┌─────────────────┐ │
    │ │ PrivateEndpoint │ │         │ │ PrivateEndpoint │ │
    │ │ 10.1.3.0/24     │ │         │ │ 10.2.3.0/24     │ │
    │ └─────────────────┘ │         │ └─────────────────┘ │
    └─────────────────────┘         └─────────────────────┘
```

---

## Network Address Space

| VNet | Address Space | Purpose |
|------|---------------|---------|
| Hub | 10.0.0.0/16 | Shared services, Bastion, Gateway |
| Spoke 1 | 10.1.0.0/16 | Workloads (VMs, apps) |
| Spoke 2 | 10.2.0.0/16 | Secondary workloads |

### Subnet Breakdown

#### Hub VNet (10.0.0.0/16)

| Subnet | Address Range | Purpose |
|--------|---------------|---------|
| AzureBastionSubnet | 10.0.0.0/26 | Azure Bastion (required name) |
| GatewaySubnet | 10.0.1.0/27 | VPN/ExpressRoute Gateway (required name) |
| SharedServicesSubnet | 10.0.2.0/24 | DNS, monitoring agents, shared services |
| AzureFirewallSubnet | 10.0.3.0/26 | Azure Firewall (required name) |

#### Spoke 1 VNet (10.1.0.0/16)

| Subnet | Address Range | Purpose |
|--------|---------------|---------|
| WorkloadSubnet | 10.1.1.0/24 | VMs, VMSS, availability sets |
| AppSubnet | 10.1.2.0/24 | App Service VNet integration, ACI |
| PrivateEndpointSubnet | 10.1.3.0/24 | Private endpoints for PaaS services |

#### Spoke 2 VNet (10.2.0.0/16)

| Subnet | Address Range | Purpose |
|--------|---------------|---------|
| WorkloadSubnet | 10.2.1.0/24 | Secondary workload VMs |
| DataSubnet | 10.2.2.0/24 | Data-tier resources |
| PrivateEndpointSubnet | 10.2.3.0/24 | Private endpoints for PaaS services |

---

## Resource Group Strategy

Each module deploys into its own resource group following the naming convention `rg-certlab-{module}`:

| Resource Group | Module | Contents |
|----------------|--------|----------|
| rg-certlab-foundation | 00-foundation | VNets, subnets, shared NSGs, tags |
| rg-certlab-identity | 01-identity | (Entra ID resources are tenant-level) |
| rg-certlab-governance | 02-governance | Policy assignments, locks, budgets |
| rg-certlab-networking | 03-networking | Peering, NSGs, ASGs, public IPs |
| rg-certlab-dns | 04-dns-connectivity | DNS zones, UDRs, Bastion, endpoints |
| rg-certlab-loadbalancing | 05-load-balancing | Load Balancer, App Gateway, Traffic Manager |
| rg-certlab-storage | 06-storage | Storage accounts, blob containers, file shares |
| rg-certlab-compute | 07-compute | VMs, VMSS, ACR, ACI, App Service |
| rg-certlab-monitoring | 08-monitoring | Log Analytics, alerts, Recovery Services |

---

## Module Dependency Diagram

```
00-foundation
├──► 01-identity          (uses resource groups)
├──► 02-governance        (uses resource groups)
├──► 03-networking        (uses foundation VNet)
│    ├──► 04-dns-connectivity   (uses VNets and subnets)
│    │    └──► 06-storage       (uses private endpoints, service endpoints)
│    ├──► 05-load-balancing     (uses VNets and subnets)
│    └──► 07-compute            (uses VNets, NSGs, subnets)
│         └──► 08-monitoring    (monitors VMs, storage, network)
```

---

## Resource Inventory by Module

### Module 00: Foundation
- 3 Virtual Networks (Hub, Spoke 1, Spoke 2)
- Subnets for each VNet
- Foundation NSGs
- Shared tags and naming conventions

### Module 01: Identity & Entra ID
- Entra ID demo users and groups
- Role assignments
- SSPR configuration (portal walkthrough)

### Module 02: Governance & Compliance
- Azure Policy assignments (audit & deny)
- Custom RBAC role definition
- Resource locks
- Budget alert ($50/month)
- Management group hierarchy

### Module 03: Virtual Networking
- VNet peering (Hub ↔ Spoke 1, Hub ↔ Spoke 2)
- NSG rules with ASGs
- Public IP addresses
- Network security rules

### Module 04: DNS & Connectivity
- Azure DNS public zone
- Azure Private DNS zone with VNet links
- Route table with UDRs
- Service endpoint (storage)
- Private endpoint (storage/Key Vault)
- Azure Bastion (Developer SKU)

### Module 05: Load Balancing
- Azure Load Balancer (Standard SKU)
- Backend pool configuration
- Traffic Manager profile
- Application Gateway (optional — expensive)

### Module 06: Storage
- 2 Storage accounts (source + replication)
- Blob containers with tiering
- Azure File share
- Lifecycle management policy
- Storage firewall rules

### Module 07: Compute
- Linux VM (availability zone)
- Windows VM (availability set)
- Virtual Machine Scale Set with autoscale
- Azure Container Registry
- Azure Container Instance
- Container App
- App Service with deployment slot

### Module 08: Monitoring & Backup
- Log Analytics workspace
- Diagnostic settings (VMs, storage)
- Alert rules with action groups
- Network Watcher flow logs
- Recovery Services vault with backup policy

---

## Identity and Access Model

```
┌─────────────────────────────────────┐
│          Microsoft Entra ID         │
│                                     │
│  Users ─► Groups ─► Role Assignments│
└──────────────────┬──────────────────┘
                   │
                   ▼
┌─────────────────────────────────────┐
│        Azure RBAC                   │
│                                     │
│  Management Group                   │
│    └── Subscription                 │
│          ├── Resource Group (module) │
│          │     └── Resources        │
│          └── Resource Group (module) │
│                └── Resources        │
└─────────────────────────────────────┘
```

- **Entra ID** manages identities (users, groups, service principals)
- **RBAC** controls access at each scope level (management group → subscription → resource group → resource)
- Lab creates demo users with scoped role assignments for hands-on RBAC exercises

---

## Monitoring Architecture

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   VMs       │  │  Storage    │  │  Network    │
│  (Module 07)│  │ (Module 06) │  │ (Module 03) │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       │  Diagnostic    │  Diagnostic    │  NSG Flow
       │  Settings      │  Settings      │  Logs
       │                │                │
       ▼                ▼                ▼
┌─────────────────────────────────────────────────┐
│         Log Analytics Workspace                 │
│         (Central Sink — Module 08)              │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │ VM Perf  │  │ Storage  │  │ Network Flow  │ │
│  │ Metrics  │  │ Metrics  │  │ Logs          │ │
│  └──────────┘  └──────────┘  └───────────────┘ │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │    Azure Monitor      │
         │  ┌─────────────────┐  │
         │  │  Alert Rules    │  │
         │  │  Action Groups  │  │
         │  │  KQL Queries    │  │
         │  └─────────────────┘  │
         └───────────────────────┘
```

- **Log Analytics Workspace** is the central sink for all diagnostic data
- Each resource sends metrics and logs via **Diagnostic Settings**
- **Alert rules** trigger on thresholds (CPU, disk, errors)
- **Action groups** define notification targets (email, webhook)
- **KQL queries** enable ad-hoc log analysis and saved searches

---

## Data Flow

### Inbound Traffic Flow
1. Internet → Public IP → Load Balancer / App Gateway → Backend VMs (Spoke 1)
2. Internet → Azure Bastion (Hub) → VM management (Spoke 1/2)

### Outbound Traffic Flow
1. VMs (Spoke) → VNet Peering → Hub → Internet (via default route or Firewall)
2. VMs (Spoke) → Private Endpoint → PaaS Services (Storage, Key Vault)

### Cross-Spoke Traffic Flow
1. Spoke 1 → Hub (peering) → Spoke 2 (peering) — requires UDR if via Firewall
2. Direct spoke-to-spoke peering is not configured (forces hub routing pattern)

### DNS Resolution Flow
1. VM → Azure-provided DNS → Public DNS zone (for public names)
2. VM → Private DNS zone (VNet-linked) → Private endpoint IPs
