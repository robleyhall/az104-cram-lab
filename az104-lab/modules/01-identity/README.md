# Module 01 — Identity & Entra ID

> **Exam weight:** 20–25 % of AZ-104 · **Deployability:** 🟡 Partially deployable

---

## 📺 Cram Session Reference

**Video:** [AZ-104 Administrator Associate Study Cram v2](https://www.youtube.com/watch?v=0Knf9nub4-k)

| Timestamp | Topic |
|-----------|-------|
| [02:20](https://www.youtube.com/watch?v=0Knf9nub4-k&t=140) | Entra ID overview |
| [05:01](https://www.youtube.com/watch?v=0Knf9nub4-k&t=301) | AD DS → Entra ID sync |
| [07:59](https://www.youtube.com/watch?v=0Knf9nub4-k&t=479) | Tenant |
| [10:21](https://www.youtube.com/watch?v=0Knf9nub4-k&t=621) | Branding |
| [11:08](https://www.youtube.com/watch?v=0Knf9nub4-k&t=668) | Users |
| [15:51](https://www.youtube.com/watch?v=0Knf9nub4-k&t=951) | Groups |
| [18:57](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1137) | Devices |
| [20:48](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1248) | Licenses |
| [23:27](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1407) | SSPR |
| [25:00](https://www.youtube.com/watch?v=0Knf9nub4-k&t=1500) | Roles |

---

## 🎯 Learning Objectives

After completing this module you will be able to:

| # | Exam Skill | Covered By |
|---|-----------|------------|
| 1 | Create users and groups | `entra-setup.sh` — creates 4 demo users and 3 groups |
| 2 | Manage user and group properties | `entra-setup.sh` — sets display names, descriptions, mail nicknames |
| 3 | Manage licenses in Microsoft Entra ID | Portal walkthrough (requires P1/P2 — see notes below) |
| 4 | Manage external users | Portal walkthrough (B2B invite flow) |
| 5 | Configure self-service password reset (SSPR) | `entra-setup.sh` — SSPR section with Portal & Graph API guidance |
| 6 | Manage built-in Azure roles | `main.bicep` — Contributor & Reader role assignments |
| 7 | Assign roles at different scopes | `main.bicep` — resource-group-scoped assignments |
| 8 | Interpret access assignments | Verify commands below |

---

## 📁 Files

| File | Purpose |
|------|---------|
| `main.bicep` | Deploys a User Assigned Managed Identity and RBAC role assignments |
| `main.bicepparam` | Parameter values for the Bicep deployment |
| `entra-setup.sh` | Creates Entra ID users, groups, group memberships, and RBAC bindings |
| `README.md` | This file |

---

## ⚠️ Prerequisites

- **Azure CLI ≥ 2.50** — `az --version`
- **Bicep CLI** — bundled with Azure CLI or install separately
- Logged in: `az login`
- Sufficient Entra ID role: **User Administrator** (for user/group management) + **Role Based Access Control Administrator** or **Owner** (for RBAC assignments)
- A resource group for the lab (see below)

> **License note:** SSPR for non-admin users, dynamic group membership, and company branding require **Entra ID P1 or P2**. You can still run the core user/group/RBAC exercises on a free tenant.  
> See [Microsoft Entra pricing](https://www.microsoft.com/security/business/microsoft-entra-pricing) for details.

---

## 🚀 Deploy

### Step 1 — Create the resource group

```bash
az group create \
  --name rg-az104-az104-lab-identity \
  --location eastus \
  --tags Environment=az104-lab Project=az104-lab Module=identity
```

### Step 2 — Run the Entra ID setup script

```bash
export DOMAIN_NAME="yourtenant.onmicrosoft.com"   # ← change this
export RESOURCE_GROUP="rg-az104-az104-lab-identity"

bash entra-setup.sh
```

The script prints the group principal IDs at the end. Copy them into `main.bicepparam`.

### Step 3 — Deploy the Bicep template

```bash
az deployment group create \
  --resource-group rg-az104-az104-lab-identity \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## ✅ Verify

### Entra ID objects

```bash
# List lab users
az ad user list \
  --filter "startswith(displayName,'CertLab')" \
  --query "[].{Name:displayName, UPN:userPrincipalName, Id:id}" -o table

# List lab groups
az ad group list \
  --filter "startswith(displayName,'az104-lab')" \
  --query "[].{Name:displayName, Id:id}" -o table

# Check group membership
az ad group member list \
  --group "az104-lab-admins" \
  --query "[].{Name:displayName, Id:id}" -o table
```

### RBAC assignments

```bash
# List role assignments on the resource group
az role assignment list \
  --resource-group rg-az104-az104-lab-identity \
  --query "[].{Principal:principalName, Role:roleDefinitionName, Scope:scope}" -o table
```

### Managed identity

```bash
# Show the managed identity
az identity show \
  --resource-group rg-az104-az104-lab-identity \
  --name az104-az104-lab-identity-uami \
  --query "{Name:name, PrincipalId:principalId, ClientId:clientId}" -o table
```

---

## 🧹 Clean Up

### Remove Entra ID objects (users, groups, RBAC)

```bash
export DOMAIN_NAME="yourtenant.onmicrosoft.com"
export RESOURCE_GROUP="rg-az104-az104-lab-identity"

bash entra-setup.sh cleanup
```

### Remove Azure resources

```bash
az group delete --name rg-az104-az104-lab-identity --yes --no-wait
```

---

## 📚 Additional Resources

- [Microsoft Entra ID documentation](https://learn.microsoft.com/en-us/azure/active-directory/)
- [Official AZ-104 Study Guide](https://learn.microsoft.com/en-us/credentials/certifications/resources/study-guides/az-104)
- [Free AZ-104 Practice Assessment](https://learn.microsoft.com/en-us/credentials/certifications/exams/az-104/practice/assessment?assessment-type=practice&assessmentId=21)
- [John Savill's AZ-104 Whiteboard](https://github.com/johnthebrit/CertificationMaterials/blob/main/whiteboards/AZ-104-Whiteboard-v2.png)
