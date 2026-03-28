# AZ-104 CertForge Lab — Task Tracker

> **Purpose:** Track project state, completed/blocked/open tasks, file inventory, and key technical decisions.

---

## Current State

- **Module 00 (Foundation):** ✅ Deployed to `rg-az104-lab-foundation` in `eastus`
- **Modules 01–08:** Not yet deployed
- **Lab workflow:** Study concepts → Deploy → Explore & Verify → Exercises (per module)

### Deployed Resources (rg-az104-lab-foundation)

| Resource | Type | Deployed By | Notes |
|----------|------|-------------|-------|
| `vnet-az104-lab-hub` | Microsoft.Network/virtualNetworks | Bicep (00-foundation/main.bicep) | Hub VNet 10.0.0.0/16 with 5 subnets |
| `vnet-az104-lab-hub-default-nsg-eastus` | Microsoft.Network/networkSecurityGroups | **Azure Policy (implicit)** | Auto-created by subscription policy on subnet creation |
| `vnet-az104-lab-hub-AzureBastionSubnet-nsg-eastus` | Microsoft.Network/networkSecurityGroups | **Azure Policy (implicit)** | Auto-created by subscription policy on subnet creation |
| `vnet-az104-lab-hub-management-nsg-eastus` | Microsoft.Network/networkSecurityGroups | **Azure Policy (implicit)** | Auto-created by subscription policy on subnet creation |

> **Note:** The 3 NSGs were NOT defined in the Bicep template. They were created automatically by an Azure Policy on the MCAPS subscription that enforces NSG association on subnet creation. The naming convention `{vnet}-{subnet}-nsg-{region}` confirms policy-driven deployment. The `GatewaySubnet` and `AzureFirewallSubnet` did not get NSGs — these special-purpose subnets are typically excluded by policy.

---

## Deployment Order (from README)

```
00-foundation          ← ✅ Deployed
├── 01-identity        ← Pending
├── 02-governance      ← Pending
├── 03-networking      ← Pending
│   ├── 04-dns-connectivity  ← Pending
│   │   └── 06-storage       ← Pending
│   ├── 05-load-balancing    ← Pending
│   └── 07-compute           ← Pending
│       └── 08-monitoring    ← Pending
```

---

## Open Tasks

- [ ] Verify foundation deployment (run verify commands from module README)
- [ ] Study Module 01 (Identity & Entra ID) concepts in LAB-GUIDE.md
- [ ] Deploy Module 01
- [ ] Complete Module 01 exercises

## Completed Tasks

- [x] Clone repository
- [x] Check prerequisites (Azure CLI, Bicep, login)
- [x] Deploy Module 00 (Foundation)
- [x] Create `.github/` folder structure
- [x] Set up `tasks/` folder with `todo.md` and `lessons.md`

---

## Key Decisions

- **Region:** `eastus` (default)
- **Subscription:** MCAPS-Hybrid-REQ-141230-2026-robleyhall
- **Lab workflow:** Following the study-first approach from LAB-GUIDE.md
