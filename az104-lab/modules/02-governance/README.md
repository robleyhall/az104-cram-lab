# Module 02: Governance & Compliance

Deploys Azure governance primitives — policies, RBAC, locks, budgets, and tagging standards. These topics represent **20–25% of the AZ-104 exam**.

## Learning Objectives

| AZ-104 Exam Skill | What You'll Practice |
|---|---|
| Create and manage Azure Policy | Assign built-in policies (audit, deny, modify effects) |
| Configure resource locks | Apply CanNotDelete lock to a resource group |
| Apply and manage tags | Enforce tags via policy, inherit tags from resource groups |
| Manage subscriptions and governance | Budget alerts, cost thresholds, spending notifications |
| Manage Azure RBAC | Create a custom role with least-privilege VM operations |
| Interpret access assignments | Understand actions vs. notActions, assignable scopes |
| Manage resource groups | Tag requirements, lock inheritance, scope hierarchy |

## 📺 Cram Session Timestamps

Video: [John Savill's AZ-104 Cram](https://www.youtube.com/watch?v=0Knf9nub4-k)

| Topic | Timestamp | Relevance |
|---|---|---|
| Clouds and Regions | [27:23](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1643s) | Region pairs, availability zones |
| Subscriptions & Management Groups | [34:48](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2088s) | Hierarchy, policy inheritance |
| Cost Analysis | [39:14](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2354s) | Budgets, alerts, cost views |
| Resource Groups | [43:31](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2611s) | Scope, tagging, locks |
| Cost Saving | [45:39](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2739s) | Reservations, spot VMs, advisor |
| Tags | [51:20](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3080s) | Tag policies, inheritance, cost tracking |
| Policy | [54:35](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3275s) | Effects, assignments, compliance |
| RBAC | [59:09](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3549s) | Roles, assignments, scope, custom roles |
| Resource Locking | [1:06:56](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4016s) | CanNotDelete vs ReadOnly, inheritance |

## What Gets Deployed

| Resource | Name | Purpose |
|---|---|---|
| Policy Assignment | `audit-unmanaged-disks` | Audit VMs not using managed disks |
| Policy Assignment | `require-env-tag-on-rg` | Require 'Environment' tag on resource groups (DoNotEnforce) |
| Policy Assignment | `inherit-env-tag-from-rg` | Auto-inherit 'Environment' tag from resource group |
| Custom RBAC Role | `CertLab VM Operator` | Start/stop/restart VMs — no delete permission |
| Resource Lock | `lock-rg-do-not-delete` | CanNotDelete lock on the resource group |
| Budget | `budget-az104-lab-governance` | $50/month budget with 80% alert threshold |

## Prerequisites

```bash
# Azure CLI and Bicep
az --version          # 2.60+ required
az bicep version      # 0.25+ required

# Logged in with sufficient permissions
az login
az account show       # Confirm correct subscription

# Required permissions: Owner or User Access Administrator
# (needed for policy assignments, RBAC role definitions, and locks)
```

## Deploy

```bash
# 1. Set variables
RESOURCE_GROUP="rg-az104-lab-governance"
LOCATION="eastus"

# 2. Create the resource group with required tags
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --tags Environment=az104-lab Project=az104-lab Module=governance CostCenter=training

# 3. Preview the deployment (what-if)
az deployment group what-if \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam

# 4. Deploy the governance resources
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name governance-$(date +%Y%m%d-%H%M%S)
```

> **💡 Tip:** Update `contactEmail` in `main.bicepparam` with your real email to receive budget alerts.

## Verify

```bash
# ── Policy Assignments ──
# List policy assignments scoped to the resource group
az policy assignment list \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, DisplayName:displayName, Enforcement:enforcementMode}" \
  --output table

# Check compliance state (may take 5-15 minutes to evaluate)
az policy state summarize \
  --resource-group $RESOURCE_GROUP \
  --output table

# ── Custom RBAC Role ──
# Verify the custom role was created
az role definition list \
  --custom-role-only true \
  --query "[?roleName=='CertLab VM Operator'].{Name:roleName, Actions:permissions[0].actions}" \
  --output table

# ── Resource Lock ──
# List locks on the resource group
az lock list \
  --resource-group $RESOURCE_GROUP \
  --output table

# ── Budget ──
# List budgets (scoped to subscription, filter by name)
az consumption budget list \
  --query "[?name=='budget-az104-lab-governance'].{Name:name, Amount:amount, TimeGrain:timeGrain}" \
  --output table

# ── Tags ──
# Show tags on the resource group
az group show --name $RESOURCE_GROUP --query tags
```

## Deploy Custom Policy Definition (Optional)

The `policy-definitions.json` file contains a custom policy that audits resources missing a `CostCenter` tag. Deploy it at the subscription level:

```bash
# Create the custom policy definition
az policy definition create \
  --name "audit-missing-costcenter-tag" \
  --display-name "Audit missing CostCenter tag" \
  --description "Audits resources that are missing a CostCenter tag" \
  --rules policy-definitions.json \
  --mode Indexed

# Assign it to the resource group
az policy assignment create \
  --name "audit-costcenter-tag" \
  --display-name "CertLab — Audit missing CostCenter tag" \
  --policy "audit-missing-costcenter-tag" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP"
```

## ⚠️ Important Notes

- **Policy propagation delay**: Policy assignments take **5–15 minutes** to evaluate compliance. The compliance state will show as "Not started" initially.
- **Tag inheritance policy**: The `inherit-env-tag-from-rg` policy uses a **Modify** effect and creates a system-assigned managed identity. This identity needs the **Tag Contributor** role (assigned automatically by Azure) to write tags on resources.
- **Custom RBAC role propagation**: Custom role definitions can take **up to 5 minutes** to propagate across Azure AD. Role assignments using this role may fail until propagation completes.
- **Resource lock**: The CanNotDelete lock **must be removed before cleanup**. Even subscription Owners cannot delete a locked resource group.
- **Budget start date**: The budget starts from the first day of the current month. Budget alerts are for notification only — they do not cap or stop spending.
- **DoNotEnforce mode**: The "Require Environment tag" policy uses `DoNotEnforce` so it audits but does not block operations in the lab. In production, change to `Default` to actively deny non-compliant deployments.

## Clean Up

```bash
# 1. Remove the resource lock first (required before deletion)
az lock delete \
  --name lock-rg-do-not-delete \
  --resource-group $RESOURCE_GROUP

# 2. Remove policy assignments
az policy assignment delete --name audit-unmanaged-disks --resource-group $RESOURCE_GROUP
az policy assignment delete --name require-env-tag-on-rg --resource-group $RESOURCE_GROUP
az policy assignment delete --name inherit-env-tag-from-rg --resource-group $RESOURCE_GROUP

# 3. Remove the custom RBAC role (must remove all assignments first)
az role definition delete --name "CertLab VM Operator"

# 4. (Optional) Remove the custom policy definition
az policy assignment delete --name audit-costcenter-tag --resource-group $RESOURCE_GROUP
az policy definition delete --name audit-missing-costcenter-tag

# 5. Delete the resource group
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## AZ-104 Exam Relevance

- **Azure Policy**: Effects (audit, deny, modify, append, deployIfNotExists), assignments, initiatives, compliance evaluation, remediation tasks
- **Resource Locks**: CanNotDelete vs ReadOnly, lock inheritance, locks override RBAC
- **Tags**: Tag policies, tag inheritance, using tags for cost management and automation
- **RBAC**: Built-in vs custom roles, role assignments, scope hierarchy (management group → subscription → resource group → resource)
- **Cost Management**: Budgets, cost alerts, cost analysis views, Azure Advisor recommendations
- **Management Groups**: Hierarchy for policy and RBAC inheritance (discussed conceptually — requires tenant-level access to deploy)
- **Resource Groups**: Region-independent containers, tag and lock scoping, moving resources between groups
