# Lessons Learned — AZ-104 CertForge Lab

> **Purpose:** Patterns, rules, and discoveries to prevent repeated mistakes and preserve institutional knowledge. Review at session start.

---

## Session: 2026-03-28

### Lesson 1: Azure Policy creates implicit resources

**What happened:** After deploying module 00-foundation (which only defines a VNet with subnets in Bicep), 3 NSGs appeared in `rg-az104-lab-foundation` that were not in the template:
- `vnet-az104-lab-hub-default-nsg-eastus`
- `vnet-az104-lab-hub-AzureBastionSubnet-nsg-eastus`
- `vnet-az104-lab-hub-management-nsg-eastus`

**Fix:** No fix needed — these are expected on MCAPS subscriptions. The subscription has a policy that auto-creates and associates NSGs with subnets on creation.

**Rule:** After every deployment, run `az resource list --resource-group <rg> -o table` to check for policy-created resources. Don't assume only Bicep-defined resources exist. Document any implicit resources in `tasks/todo.md`.

**Customer talking point:** Enterprise Azure subscriptions often have policies that auto-deploy security resources (NSGs, diagnostic settings, etc.) when you create infrastructure. The naming pattern `{vnet}-{subnet}-nsg-{region}` is a giveaway. Special-purpose subnets like `GatewaySubnet` and `AzureFirewallSubnet` are typically excluded from these policies.

### Lesson 2: Naming convention should be established early

**What happened:** Resources were initially deployed with `certlab` naming, then renamed to `az104-lab` across 52 files. This required destroying and redeploying Azure resources.

**Fix:** Global find-and-replace of `certlab` → `az104-lab` across all Bicep, scripts, exercises, docs, and the CertForge prompt. Destroyed `rg-certlab-foundation` and redeployed as `rg-az104-lab-foundation`.

**Rule:** Establish the naming convention before deploying any resources. Renaming after deployment requires destroy/redeploy cycles. Update the CertForge prompt's naming convention if changing the default.

**Commit:** `b69bc9f`
