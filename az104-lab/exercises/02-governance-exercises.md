# Exercise 02: Governance & Compliance

[🎥 Cram Session: Governance (27:23–1:09:28)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1643s)

> **Exam Domain**: Manage Azure identities and governance (20–25%)
>
> These exercises cover Azure Policy, RBAC, resource locks, tags, budgets, and management groups.

---

## Prerequisites

- An active Azure subscription with **Owner** role
- Azure CLI v2.60+ authenticated (`az login`)
- Module 00 (Foundation) deployed
- A resource group to experiment with: `rg-az104-lab-governance`

```bash
az group create --name rg-az104-lab-governance --location eastus \
  --tags Environment=az104-lab Module=governance
```

---

## Exercise 2.1: Create and Assign an Azure Policy (Require Tags)

**Difficulty**: 🟢 Guided

**Objectives**:
- Find and assign a built-in policy definition
- Understand policy effects (Audit vs Deny)
- Test policy enforcement

[🎥 Azure Policy (54:35)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3275s)

**Steps**:

1. List built-in policies related to tags:
   ```bash
   az policy definition list \
     --query "[?contains(displayName,'tag') && policyType=='BuiltIn'].{name:displayName, effect:policyRule.then.effect}" \
     --output table | head -20
   ```

2. Find the "Require a tag and its value on resources" policy:
   ```bash
   POLICY_DEF=$(az policy definition list \
     --query "[?displayName=='Require a tag and its value on resources'].name" -o tsv)
   echo "Policy definition ID: $POLICY_DEF"
   ```

3. Assign the policy with **Audit** effect first (safer for testing):
   ```bash
   az policy assignment create \
     --name "audit-env-tag" \
     --display-name "Audit: Resources must have Environment tag" \
     --policy "$POLICY_DEF" \
     --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-az104-lab-governance" \
     --params '{"tagName": {"value": "Environment"}, "tagValue": {"value": "az104-lab"}}'
   ```

4. Check compliance (may take 5–15 minutes for initial evaluation):
   ```bash
   az policy state summarize \
     --resource-group rg-az104-lab-governance \
     --query "results.{compliant:resourceDetails[?complianceState=='Compliant'].count | [0], nonCompliant:resourceDetails[?complianceState=='NonCompliant'].count | [0]}"
   ```

5. Create a resource without the required tag to test:
   ```bash
   az storage account create \
     --name "stgov$(date +%s | tail -c 9)" \
     --resource-group rg-az104-lab-governance \
     --sku Standard_LRS \
     --location eastus
   # This should succeed with Audit (logged but not blocked)
   ```

6. Now update the assignment to **Deny** and test again:
   ```bash
   az policy assignment delete --name "audit-env-tag" \
     --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-az104-lab-governance"

   # Use the "Require a tag on resources" definition with Deny
   DENY_POLICY=$(az policy definition list \
     --query "[?displayName=='Require a tag on resources'].name" -o tsv)

   az policy assignment create \
     --name "deny-env-tag" \
     --display-name "Deny: Resources must have Environment tag" \
     --policy "$DENY_POLICY" \
     --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-az104-lab-governance" \
     --params '{"tagName": {"value": "Environment"}}' \
     --enforcement-mode Default
   ```

7. Test the deny policy (wait ~2 minutes for policy to take effect):
   ```bash
   # This should FAIL because no Environment tag is provided
   az storage account create \
     --name "stgov$(date +%s | tail -c 9)" \
     --resource-group rg-az104-lab-governance \
     --sku Standard_LRS \
     --location eastus

   # This should SUCCEED because the tag is included
   az storage account create \
     --name "stgov$(date +%s | tail -c 9)" \
     --resource-group rg-az104-lab-governance \
     --sku Standard_LRS \
     --location eastus \
     --tags Environment=az104-lab
   ```

**Success Criteria**:
- [ ] Audit policy assignment shows non-compliant resources
- [ ] Deny policy blocks resource creation without required tags
- [ ] Resource creation succeeds when the required tag is present

> 💡 **Exam Tip**: Know all policy effects and when to use each:
> - **Audit**: Log non-compliance but allow the action
> - **Deny**: Block non-compliant actions
> - **DeployIfNotExists**: Auto-remediate by deploying resources
> - **Modify**: Change resource properties during creation/update
> - **Append**: Add fields to a resource during creation/update
>
> The exam often asks: "Which effect should you use to *enforce* vs *monitor* compliance?"

---

## Exercise 2.2: Apply Resource Locks and Test Them

**Difficulty**: 🟢 Guided

**Objectives**:
- Create ReadOnly and Delete locks
- Test what each lock type prevents
- Understand lock inheritance

[🎥 Resource Locking (1:06:56)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=4016s)

**Steps**:

1. Apply a **Delete** lock to the resource group:
   ```bash
   az lock create \
     --name "no-delete-rg" \
     --resource-group rg-az104-lab-governance \
     --lock-type CanNotDelete \
     --notes "Prevent accidental deletion of governance lab resources"
   ```

2. Try to delete the resource group (should fail):
   ```bash
   az group delete --name rg-az104-lab-governance --yes 2>&1 || echo "⛔ Delete blocked by lock!"
   ```

3. Verify you can still modify resources (Delete lock allows modifications):
   ```bash
   az group update --name rg-az104-lab-governance \
     --tags Environment=az104-lab Module=governance Updated=true
   echo "✅ Modification succeeded — Delete lock only prevents deletion"
   ```

4. Add a **ReadOnly** lock to the resource group:
   ```bash
   az lock create \
     --name "readonly-rg" \
     --resource-group rg-az104-lab-governance \
     --lock-type ReadOnly \
     --notes "Prevent any modifications to governance lab resources"
   ```

5. Try to modify the resource group (should fail):
   ```bash
   az group update --name rg-az104-lab-governance \
     --tags Environment=az104-lab Module=governance Updated=false 2>&1 \
     || echo "⛔ Modification blocked by ReadOnly lock!"
   ```

6. List all locks:
   ```bash
   az lock list --resource-group rg-az104-lab-governance --output table
   ```

7. Remove the ReadOnly lock (keep the Delete lock for now):
   ```bash
   az lock delete --name "readonly-rg" --resource-group rg-az104-lab-governance
   ```

**Success Criteria**:
- [ ] Delete lock prevents resource group deletion
- [ ] Delete lock allows resource modifications
- [ ] ReadOnly lock prevents both deletion AND modifications
- [ ] You can explain lock inheritance (locks on RG apply to all child resources)

> 💡 **Exam Tip**: **ReadOnly** is more restrictive than **CanNotDelete**. ReadOnly prevents modifications AND deletion. Locks are **inherited** — a lock on a resource group applies to all resources within it. Even an **Owner** cannot bypass a lock without first removing it.

> ⚠️ **Common Mistake**: ReadOnly locks can break unexpected things. For example, a ReadOnly lock on a storage account prevents listing keys (which is a POST operation), so applications that rotate keys will fail.

---

## Exercise 2.3: Create a Custom RBAC Role

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Understand the structure of a custom RBAC role definition
- Create a custom role that allows starting/stopping VMs but not deleting them
- Assign the role to a user at a resource group scope

[🎥 RBAC (59:09)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=3549s)

**Steps**:

1. Examine a built-in role to understand the structure:
   ```bash
   az role definition list --name "Virtual Machine Contributor" \
     --query "[0].{name:roleName, actions:permissions[0].actions, notActions:permissions[0].notActions}" \
     --output json
   ```

2. Create a custom role definition file:
   ```bash
   SUB_ID=$(az account show --query id -o tsv)
   cat > vm-operator-role.json << EOF
   {
     "Name": "VM Operator",
     "Description": "Can start, stop, and restart VMs but cannot create or delete them",
     "Actions": [
       "Microsoft.Compute/virtualMachines/start/action",
       "Microsoft.Compute/virtualMachines/powerOff/action",
       "Microsoft.Compute/virtualMachines/restart/action",
       "Microsoft.Compute/virtualMachines/read",
       "Microsoft.Compute/virtualMachines/instanceView/read",
       "Microsoft.Network/networkInterfaces/read",
       "Microsoft.Resources/subscriptions/resourceGroups/read"
     ],
     "NotActions": [],
     "AssignableScopes": [
       "/subscriptions/$SUB_ID"
     ]
   }
   EOF
   ```

3. Create the custom role:
   ```bash
   az role definition create --role-definition vm-operator-role.json
   ```

4. Verify the role was created:
   ```bash
   az role definition list --name "VM Operator" --output table
   ```

5. Assign the role to labuser1 at the resource group scope:
   ```bash
   az role assignment create \
     --assignee "labuser1@${DOMAIN}" \
     --role "VM Operator" \
     --scope "/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance"
   ```

6. Verify the assignment:
   ```bash
   az role assignment list \
     --resource-group rg-az104-lab-governance \
     --query "[?roleDefinitionName=='VM Operator'].{principal:principalName, role:roleDefinitionName, scope:scope}" \
     --output table
   ```

**Success Criteria**:
- [ ] Custom "VM Operator" role exists with correct Actions
- [ ] Role is assigned to labuser1 at the resource group scope
- [ ] You can explain the difference between Actions, NotActions, DataActions, and NotDataActions

> 💡 **Exam Tip**: Custom roles require `Microsoft.Authorization/roleDefinitions/write` permission. **AssignableScopes** limits where the role can be assigned — it does NOT grant the permissions at those scopes. The exam tests this distinction. Also remember: RBAC is **additive** — if a user has two roles, they get the union of all permissions.

> ⚠️ **Common Mistake**: Confusing `NotActions` with deny. `NotActions` is a convenience for subtraction from `Actions` wildcards — it does NOT deny access. Use **Azure deny assignments** (limited availability) for true deny.

---

## Exercise 2.4: Set Up a Budget with Alerts

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a budget for the resource group
- Configure alert thresholds and notification emails
- Understand cost management concepts

[🎥 Cost Analysis and Budgets (39:14)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=2354s)

**Steps**:

1. View current costs for the resource group:
   ```bash
   az consumption usage list \
     --query "[?contains(instanceName,'az104-lab')].{resource:instanceName, cost:pretaxCost, currency:currency}" \
     --output table 2>/dev/null || echo "ℹ️ No cost data yet (may take 24h to populate)"
   ```

2. Create a monthly budget:
   ```bash
   SUB_ID=$(az account show --query id -o tsv)
   START_DATE=$(date -u +"%Y-%m-01T00:00:00Z")
   az consumption budget create \
     --budget-name "az104-lab-monthly" \
     --amount 50 \
     --category Cost \
     --time-grain Monthly \
     --start-date "$START_DATE" \
     --resource-group rg-az104-lab-governance
   ```

3. If the CLI budget command is not available, use ARM REST API:
   ```bash
   SUB_ID=$(az account show --query id -o tsv)
   START_DATE=$(date -u +"%Y-%m-01T00:00:00Z")

   az rest --method put \
     --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance/providers/Microsoft.Consumption/budgets/az104-lab-monthly?api-version=2023-11-01" \
     --body "{
       \"properties\": {
         \"category\": \"Cost\",
         \"amount\": 50,
         \"timeGrain\": \"Monthly\",
         \"timePeriod\": {
           \"startDate\": \"$START_DATE\"
         },
         \"notifications\": {
           \"alert50pct\": {
             \"enabled\": true,
             \"operator\": \"GreaterThanOrEqualTo\",
             \"threshold\": 50,
             \"contactEmails\": [\"admin@yourdomain.com\"]
           },
           \"alert80pct\": {
             \"enabled\": true,
             \"operator\": \"GreaterThanOrEqualTo\",
             \"threshold\": 80,
             \"contactEmails\": [\"admin@yourdomain.com\"]
           },
           \"alert100pct\": {
             \"enabled\": true,
             \"operator\": \"GreaterThanOrEqualTo\",
             \"threshold\": 100,
             \"contactEmails\": [\"admin@yourdomain.com\"]
           }
         }
       }
     }"
   ```

4. Verify the budget was created:
   ```bash
   az rest --method get \
     --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance/providers/Microsoft.Consumption/budgets?api-version=2023-11-01" \
     --query "value[].{name:name, amount:properties.amount, grain:properties.timeGrain}"
   ```

**Success Criteria**:
- [ ] Budget "az104-lab-monthly" exists with $50 limit
- [ ] Three alert thresholds configured (50%, 80%, 100%)
- [ ] You can explain the difference between budgets (alerts only) and spending limits (hard stops)

> 💡 **Exam Tip**: Budgets send **notifications only** — they do NOT stop spending. Azure spending limits (available on some subscription types) can stop spending. The exam tests this distinction. Also know: **Azure Advisor** provides cost optimization recommendations (right-sizing, reserved instances, etc.).

> 📖 **Deep Dive**: [Azure Cost Management](https://learn.microsoft.com/en-us/azure/cost-management-billing/)

---

## Exercise 2.5: Interpret Access Assignments

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Determine who has access to a resource and why
- Trace role assignments through scope inheritance
- Use `az role assignment list` effectively

**Steps**:

1. List ALL role assignments on the resource group:
   ```bash
   az role assignment list \
     --resource-group rg-az104-lab-governance \
     --include-inherited \
     --output table
   ```

2. For each assignment, identify the source scope:
   ```bash
   az role assignment list \
     --resource-group rg-az104-lab-governance \
     --include-inherited \
     --query "[].{principal:principalName, role:roleDefinitionName, scope:scope, type:principalType}" \
     --output table
   ```

3. Check what permissions a specific user has:
   ```bash
   # Check your own permissions
   az role assignment list \
     --assignee "$(az ad signed-in-user show --query id -o tsv)" \
     --all \
     --query "[].{role:roleDefinitionName, scope:scope}" \
     --output table
   ```

4. Investigate inherited assignments — filter by scope level:
   ```bash
   SUB_ID=$(az account show --query id -o tsv)

   echo "=== Assignments inherited from subscription ==="
   az role assignment list \
     --resource-group rg-az104-lab-governance \
     --include-inherited \
     --query "[?contains(scope,'subscriptions') && !contains(scope,'resourceGroups')]" \
     --output table

   echo "=== Assignments at resource group level ==="
   az role assignment list \
     --resource-group rg-az104-lab-governance \
     --query "[?contains(scope,'resourceGroups')]" \
     --output table
   ```

5. **Question to answer**: If a user has "Reader" at the subscription level and "Contributor" at the resource group level, what effective access do they have at the resource group?

**Success Criteria**:
- [ ] You can list all role assignments including inherited ones
- [ ] You can distinguish between direct and inherited role assignments
- [ ] You correctly answered: "Contributor" — RBAC is additive, so the user gets the union of both roles

> 💡 **Exam Tip**: RBAC inheritance flows: **Management Group → Subscription → Resource Group → Resource**. Permissions are **additive** across scopes — there is no "deny" at a higher scope that blocks a lower scope assignment (except for explicit deny assignments, which are rare). The exam frequently asks "given these role assignments at different scopes, what can the user do?"

---

## Exercise 2.6: Design a Management Group Hierarchy

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a management group hierarchy for a multi-subscription organization
- Apply policies at appropriate levels
- Understand governance inheritance

**Scenario**:

> *"A developer accidentally deleted a production database. Design the governance controls to prevent this from happening again."*

Your organization has:
- **3 environments**: Development, Staging, Production
- **2 business units**: Retail, Corporate
- **6 subscriptions** total (one per environment per BU)
- **Requirements**:
  - All resources must have an `Environment` and `CostCenter` tag
  - Production resources cannot be deleted without authorization
  - Dev environments have a $500/month spending cap alert
  - Only specific VM sizes allowed in production

**Your Task**:

1. Design the management group hierarchy (draw it as ASCII art):
   ```
   Tenant Root Group
   └── org-contoso
       ├── mg-retail
       │   ├── sub-retail-dev
       │   ├── sub-retail-staging
       │   └── sub-retail-prod
       └── mg-corporate
           ├── sub-corporate-dev
           ├── sub-corporate-staging
           └── sub-corporate-prod
   ```

2. Determine which policies go at which level:

   | Policy | Scope | Effect | Justification |
   |--------|-------|--------|---------------|
   | Require Environment tag | ? | ? | ? |
   | Require CostCenter tag | ? | ? | ? |
   | Delete locks on production | ? | ? | ? |
   | Budget alerts for dev | ? | ? | ? |
   | Allowed VM sizes (prod) | ? | ? | ? |

3. Implement the management group structure:
   ```bash
   # Create management groups
   az account management-group create --name "org-contoso" --display-name "Contoso Organization"
   az account management-group create --name "mg-retail" --display-name "Retail" --parent "org-contoso"
   az account management-group create --name "mg-corporate" --display-name "Corporate" --parent "org-contoso"

   # Verify hierarchy
   az account management-group show --name "org-contoso" --expand --recurse --output json
   ```

4. Apply tag policies at the organization level:
   ```bash
   POLICY_DEF=$(az policy definition list \
     --query "[?displayName=='Require a tag on resources'].name" -o tsv)

   # Apply at the org level — inherits to all subscriptions
   az policy assignment create \
     --name "require-env-tag" \
     --display-name "Require Environment tag on all resources" \
     --policy "$POLICY_DEF" \
     --scope "/providers/Microsoft.Management/managementGroups/org-contoso" \
     --params '{"tagName": {"value": "Environment"}}'
   ```

**Design Document** (fill in):
```
Hierarchy Design:
  [Your ASCII diagram]

Policy Placement:
  [Table with policy → scope → effect mapping]

Lock Strategy:
  [Where to apply locks and of what type]

Prevention Analysis:
  [How this would have prevented the database deletion]
```

**Success Criteria**:
- [ ] Management group hierarchy is created
- [ ] Policies are assigned at the correct scope levels
- [ ] You can explain how governance inheritance prevents the scenario
- [ ] You addressed: tag enforcement, deletion prevention, cost control, VM size restriction

> 💡 **Exam Tip**: Management groups support up to **6 levels of depth** (not counting the root). Policies and RBAC assigned at a management group inherit to all child subscriptions and resources. The exam tests hierarchy design — remember that policies at higher scopes **cannot be overridden** by lower scopes.

---

## Exercise 2.7: Create a Custom Policy for Naming Conventions

**Difficulty**: 🔴 Challenge

**Objectives**:
- Write a custom policy definition using JSON
- Understand policy rule syntax (field, condition, effect)
- Deploy and test the custom policy

**Steps**:

1. Create a custom policy that enforces a naming prefix:
   ```bash
   SUB_ID=$(az account show --query id -o tsv)

   cat > naming-policy.json << 'EOF'
   {
     "properties": {
       "displayName": "Enforce resource naming prefix",
       "description": "All resources must start with a valid prefix (rg-, st, vm-, vnet-, nsg-, pip-)",
       "mode": "All",
       "policyRule": {
         "if": {
           "not": {
             "anyOf": [
               { "field": "name", "like": "rg-*" },
               { "field": "name", "like": "st*" },
               { "field": "name", "like": "vm-*" },
               { "field": "name", "like": "vnet-*" },
               { "field": "name", "like": "nsg-*" },
               { "field": "name", "like": "pip-*" },
               { "field": "name", "like": "lb-*" },
               { "field": "name", "like": "asg-*" },
               { "field": "name", "like": "kv-*" },
               { "field": "name", "like": "log-*" }
             ]
           }
         },
         "then": {
           "effect": "deny"
         }
       }
     }
   }
   EOF
   ```

2. Create the policy definition:
   ```bash
   az policy definition create \
     --name "enforce-naming" \
     --display-name "Enforce resource naming prefix" \
     --rules naming-policy.json \
     --mode All
   ```

3. Assign the policy to your test resource group:
   ```bash
   az policy assignment create \
     --name "enforce-naming-gov" \
     --policy "enforce-naming" \
     --scope "/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance"
   ```

4. Test the policy:
   ```bash
   # Should FAIL — name doesn't start with an approved prefix
   az network nsg create --name "my-bad-nsg" \
     --resource-group rg-az104-lab-governance 2>&1 || echo "⛔ Blocked by naming policy!"

   # Should SUCCEED — name starts with "nsg-"
   az network nsg create --name "nsg-az104-lab-test" \
     --resource-group rg-az104-lab-governance \
     --tags Environment=az104-lab
   ```

5. **Challenge extension**: Modify the policy to use **Audit** instead of **Deny** and add a parameter for the allowed prefixes so it's reusable across different resource types.

**Success Criteria**:
- [ ] Custom policy definition is created
- [ ] Policy correctly blocks resources with invalid naming
- [ ] Policy allows resources with valid naming prefixes
- [ ] You can modify the policy rule syntax confidently

> ⚠️ **Common Mistake**: Custom policies in `"mode": "All"` apply to all resource types including those that don't support tags. Use `"mode": "Indexed"` if your policy relates to tags or locations — this excludes resource types that don't support tags.

> 📖 **Deep Dive**: [Azure Policy Definition Structure](https://learn.microsoft.com/en-us/azure/governance/policy/)

---

## Clean Up

```bash
# Remove policy assignments
SUB_ID=$(az account show --query id -o tsv)
az policy assignment delete --name "audit-env-tag" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance" 2>/dev/null
az policy assignment delete --name "deny-env-tag" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance" 2>/dev/null
az policy assignment delete --name "enforce-naming-gov" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-az104-lab-governance" 2>/dev/null
az policy assignment delete --name "require-env-tag" \
  --scope "/providers/Microsoft.Management/managementGroups/org-contoso" 2>/dev/null

# Remove custom policy definition
az policy definition delete --name "enforce-naming" 2>/dev/null

# Remove custom RBAC role
az role definition delete --name "VM Operator" 2>/dev/null

# Remove locks (must remove locks before deleting RG)
az lock delete --name "no-delete-rg" --resource-group rg-az104-lab-governance 2>/dev/null
az lock delete --name "readonly-rg" --resource-group rg-az104-lab-governance 2>/dev/null

# Remove management groups (children first)
az account management-group delete --name "mg-retail" 2>/dev/null
az account management-group delete --name "mg-corporate" 2>/dev/null
az account management-group delete --name "org-contoso" 2>/dev/null

# Remove resource group
az group delete --name rg-az104-lab-governance --yes --no-wait

# Clean up local files
rm -f vm-operator-role.json naming-policy.json

echo "✅ Governance lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| Policy Effects | **Deny** (block), **Audit** (log), **DeployIfNotExists** (auto-remediate), **Modify** (alter properties), **Append** (add fields) |
| RBAC Inheritance | Management Group → Subscription → Resource Group → Resource |
| RBAC is Additive | Multiple roles = union of all permissions; no implicit deny |
| Lock Types | **CanNotDelete** (prevent deletion), **ReadOnly** (prevent all changes) |
| Lock Inheritance | Locks on RG apply to all resources within |
| Custom Roles | Require `Microsoft.Authorization/roleDefinitions/write`; define with Actions/NotActions |
| Management Groups | Up to 6 levels deep; policies and RBAC inherit downward |
| Budgets | **Notification only** — they do NOT stop spending |

---

*Previous: [Exercise 01 — Identity](01-identity-exercises.md) | Next: [Exercise 03 — Networking](03-networking-exercises.md)*
