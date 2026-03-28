# Cleanup Guide

> ⚠️ **Warning**: Azure resources incur costs even when idle. Always clean up lab resources when you're done studying to avoid unexpected charges.

---

## Option 1: Destroy Everything

The fastest way to remove all lab resources:

```bash
./scripts/destroy-all.sh
```

This script deletes all `rg-az104-lab-*` resource groups and cleans up Entra ID demo objects.

---

## Option 2: Destroy a Specific Module

Remove resources from a single module while keeping others intact:

```bash
./scripts/destroy-module.sh {module-name}
```

Examples:
```bash
./scripts/destroy-module.sh 05-load-balancing    # Remove LB, App GW, Traffic Manager
./scripts/destroy-module.sh 04-dns-connectivity   # Remove Bastion, DNS, endpoints
./scripts/destroy-module.sh 07-compute            # Remove VMs, VMSS, containers
```

---

## Option 3: Manual Cleanup via Azure CLI

### List All Lab Resource Groups

```bash
az group list --query "[?starts_with(name, 'rg-az104-lab')]" -o table
```

### Delete Individual Resource Groups

```bash
az group delete --name rg-az104-lab-monitoring --yes --no-wait
az group delete --name rg-az104-lab-compute --yes --no-wait
az group delete --name rg-az104-lab-storage --yes --no-wait
az group delete --name rg-az104-lab-loadbalancing --yes --no-wait
az group delete --name rg-az104-lab-dns --yes --no-wait
az group delete --name rg-az104-lab-networking --yes --no-wait
az group delete --name rg-az104-lab-governance --yes --no-wait
az group delete --name rg-az104-lab-identity --yes --no-wait
az group delete --name rg-az104-lab-foundation --yes --no-wait
```

> 💡 Using `--no-wait` allows deletions to run in parallel. Resource group deletion can take 5–15 minutes.

---

## Cleanup Order

Delete in **reverse deployment order** to respect dependencies:

| Order | Resource Group | Module |
|-------|---------------|--------|
| 1 | rg-az104-lab-monitoring | 08-monitoring |
| 2 | rg-az104-lab-compute | 07-compute |
| 3 | rg-az104-lab-storage | 06-storage |
| 4 | rg-az104-lab-loadbalancing | 05-load-balancing |
| 5 | rg-az104-lab-dns | 04-dns-connectivity |
| 6 | rg-az104-lab-networking | 03-networking |
| 7 | rg-az104-lab-governance | 02-governance |
| 8 | rg-az104-lab-identity | 01-identity |
| 9 | rg-az104-lab-foundation | 00-foundation |

---

## Verify Cleanup

After cleanup, verify no lab resources remain:

```bash
# Check for remaining resource groups
az group list --query "[?starts_with(name, 'rg-az104-lab')]" -o table

# Check for any remaining resources (should return empty)
az resource list --query "[?contains(name, 'az104-lab')]" -o table

# Check for remaining policy assignments
az policy assignment list --query "[?contains(displayName, 'az104-lab')]" -o table

# Check for remaining role assignments (custom roles)
az role definition list --custom-role-only true --query "[?contains(roleName, 'az104-lab')]" -o table
```

If any resources remain, delete them manually or re-run the destroy scripts.

---

## Entra ID Cleanup

Demo users and groups created in Module 01 are tenant-level resources and are **not** removed by resource group deletion.

### Remove Demo Users

```bash
# List demo users
az ad user list --query "[?startsWith(mailNickname, 'az104-lab')]" -o table

# Delete demo users
az ad user list --query "[?startsWith(mailNickname, 'az104-lab')].id" -o tsv | while read id; do
  az ad user delete --id "$id"
done
```

### Remove Demo Groups

```bash
# List demo groups
az ad group list --query "[?startsWith(displayName, 'CertLab')]" -o table

# Delete demo groups
az ad group list --query "[?startsWith(displayName, 'CertLab')].id" -o tsv | while read id; do
  az ad group delete --group "$id"
done
```

### Remove App Registrations (if any)

```bash
az ad app list --query "[?startsWith(displayName, 'az104-lab')]" -o table
az ad app list --query "[?startsWith(displayName, 'az104-lab')].id" -o tsv | while read id; do
  az ad app delete --id "$id"
done
```

---

## Soft-Deleted Resources

Some Azure resources support **soft delete** and will remain recoverable (and may still incur costs) after deletion:

### Key Vault

Key Vaults are soft-deleted by default and retained for 90 days:

```bash
# List soft-deleted vaults
az keyvault list-deleted --query "[?contains(name, 'az104-lab')]" -o table

# Purge a soft-deleted vault (permanent deletion)
az keyvault purge --name {vault-name}
```

### Recovery Services Vault

Recovery Services vaults require all backup items to be removed before the vault can be deleted:

```bash
# List backup items in the vault
az backup item list --resource-group rg-az104-lab-monitoring --vault-name {vault-name} -o table

# Disable and delete backup for each item first
az backup protection disable --resource-group rg-az104-lab-monitoring \
  --vault-name {vault-name} \
  --container-name {container} \
  --item-name {item} \
  --delete-backup-data true --yes

# Then delete the vault
az backup vault delete --resource-group rg-az104-lab-monitoring --name {vault-name} --yes
```

### Storage Accounts with Soft Delete

Blobs and containers with soft delete enabled retain data after deletion:

```bash
# Check soft-delete status
az storage blob service-properties show --account-name {account} --query deleteRetentionPolicy
```

> 💡 Resource group deletion handles most of this automatically, but soft-deleted Key Vaults persist at the subscription level.

---

## Final Verification

Run this comprehensive check to confirm everything is cleaned up:

```bash
echo "=== Checking for remaining az104-lab resources ==="
echo ""
echo "Resource Groups:"
az group list --query "[?starts_with(name, 'rg-az104-lab')].[name]" -o tsv
echo ""
echo "Entra ID Users:"
az ad user list --query "[?startsWith(mailNickname, 'az104-lab')].[displayName]" -o tsv
echo ""
echo "Entra ID Groups:"
az ad group list --query "[?startsWith(displayName, 'CertLab')].[displayName]" -o tsv
echo ""
echo "Soft-deleted Key Vaults:"
az keyvault list-deleted --query "[?contains(name, 'az104-lab')].[name]" -o tsv
echo ""
echo "Policy Assignments:"
az policy assignment list --query "[?contains(displayName, 'az104-lab')].[displayName]" -o tsv
echo ""
echo "=== Cleanup verification complete ==="
```

If all outputs are empty, your environment is fully cleaned up. ✅
