# Module 06: Storage

Azure Storage accounts, blob containers, file shares, lifecycle management, SAS tokens, encryption, and replication for the AZ-104 certification lab. Storage topics represent **15–20 %** of the exam.

## 🎯 Learning Objectives

After completing this module you will be able to:

| Exam Skill | Covered |
|---|---|
| Create and configure storage accounts | ✅ |
| Configure storage redundancy (LRS/ZRS/GRS/RA-GRS/GZRS/RA-GZRS) | ✅ |
| Configure blob containers and access levels | ✅ |
| Configure blob access tiers (Hot/Cool/Cold/Archive) | ✅ |
| Configure blob lifecycle management policies | ✅ |
| Configure blob soft delete and versioning | ✅ |
| Configure object replication | ✅ |
| Configure Azure Files shares | ✅ |
| Configure storage firewalls and virtual networks | ✅ |
| Configure shared access signatures (SAS tokens) | ✅ |
| Configure stored access policies | ✅ |
| Manage access keys | ✅ |
| Configure identity-based access for storage | ✅ |
| Configure encryption (Microsoft-managed vs customer-managed keys) | ✅ |
| Use Azure Storage Explorer and AzCopy | ✅ |

## 📐 What Gets Deployed

| Resource | Name | Purpose |
|---|---|---|
| Storage Account (primary) | `staz104-labpri{suffix}` | Main storage — blobs, files, lifecycle management |
| Blob Container | `az104-lab-data` | Private container for lab data |
| Blob Container | `az104-lab-public` | Blob-level public access (anonymous read demo) |
| File Share | `az104-lab-files` | Azure Files share (5 GB, Hot tier) |
| Lifecycle Policy | 3 rules | Cool → 30 d, Archive → 90 d, Delete → 365 d |
| Storage Account (replica) | `staz104-labrep{suffix}` | Object replication destination |
| Blob Container | `az104-lab-data-replica` | Replica container |

## 🔄 Storage Redundancy Comparison

| Type | Copies | Durability (annual) | Cross-Region | Notes |
|---|---|---|---|---|
| **LRS** | 3 | 11 nines (99.999999999 %) | No | Lowest cost; single datacenter |
| **ZRS** | 3 | 12 nines | No | Spread across 3 availability zones |
| **GRS** | 6 | 16 nines | Yes (read after failover) | 3 local + 3 in paired region |
| **RA-GRS** | 6 | 16 nines | Yes (read anytime) | Read-access to secondary region |
| **GZRS** | 6 | 16 nines | Yes (zone + region) | ZRS locally + GRS to paired region |
| **RA-GZRS** | 6 | 16 nines | Yes (zone + region, read anytime) | Highest durability and availability |

> **Exam tip:** Know when to recommend each redundancy option. LRS/ZRS protect against hardware failures. GRS/GZRS protect against regional disasters. RA- variants provide read access to the secondary without failover.

## 🌡️ Blob Access Tier Comparison

| Tier | Storage Cost | Access Cost | Min Retention | Retrieval Latency | Use Case |
|---|---|---|---|---|---|
| **Hot** | Highest | Lowest | None | Milliseconds | Frequently accessed data |
| **Cool** | Lower | Higher | 30 days | Milliseconds | Infrequent access (≥ 30 d) |
| **Cold** | Even lower | Even higher | 90 days | Milliseconds | Rare access (≥ 90 d) |
| **Archive** | Lowest | Highest | 180 days | Hours (rehydrate) | Long-term backup / compliance |

> **Exam tip:** Archive tier is offline — blobs must be rehydrated (to Hot or Cool) before reading. Rehydration can take up to 15 hours (standard) or under 1 hour (high priority, higher cost).

## 📺 Savill AZ-104 Cram Timestamps

| Topic | Timestamp | Link |
|---|---|---|
| Storage accounts | 2:31:50 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9110s) |
| Storage tools | 2:42:07 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9727s) |
| Blob tiering | 2:44:20 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9860s) |
| Lifecycle management | 2:49:05 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10145s) |
| Object replication | 2:50:22 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10222s) |
| Azure Files | 2:52:45 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10365s) |
| Access (SAS, keys, RBAC) | 2:56:41 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10601s) |
| Encryption | 3:00:30 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10830s) |
| Managed disks | 3:02:54 | [▶️](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10974s) |

🎥 Full video: [John Savill's AZ-104 Cram](https://www.youtube.com/watch?v=0Knf9nub4-k)

## Prerequisites

- Azure CLI (v2.60+) with Bicep
- Resource group from Module 00 (`rg-az104-lab-eastus`)
- Networking deployed (Module 03) — you need the spoke1/data subnet resource ID

## 🚀 Deploy

```bash
# Set variables
RG="rg-az104-lab-eastus"

# Get the data subnet ID from the networking module
DATA_SUBNET_ID=$(az network vnet subnet show \
  --resource-group "$RG" \
  --vnet-name vnet-az104-lab-spoke1 \
  --name data \
  --query id -o tsv)

# Preview changes
az deployment group create \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters dataSubnetId="$DATA_SUBNET_ID" \
  --what-if

# Deploy
az deployment group create \
  --resource-group "$RG" \
  --template-file main.bicep \
  --parameters dataSubnetId="$DATA_SUBNET_ID" \
  --query 'properties.outputs' -o json
```

## ✅ Verify Deployment

```bash
RG="rg-az104-lab-eastus"

# List storage accounts
az storage account list \
  --resource-group "$RG" \
  --query "[?contains(name,'az104-lab')].{Name:name, Kind:kind, SKU:sku.name, Tier:accessTier}" \
  -o table

# Get primary account name
PRIMARY=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labpri')].name" -o tsv)

# Verify blob containers
az storage container list \
  --account-name "$PRIMARY" \
  --auth-mode login \
  --query "[].{Name:name, PublicAccess:properties.publicAccess}" \
  -o table

# Verify file share
az storage share-rm list \
  --storage-account "$PRIMARY" \
  --resource-group "$RG" \
  --query "[].{Name:name, Quota:properties.shareQuota, Tier:properties.accessTier}" \
  -o table

# Verify lifecycle management policy
az storage account management-policy show \
  --account-name "$PRIMARY" \
  --resource-group "$RG" \
  --query "policy.rules[].{Name:name, TierToCool:definition.actions.baseBlob.tierToCool, TierToArchive:definition.actions.baseBlob.tierToArchive, Delete:definition.actions.baseBlob.delete}" \
  -o table

# Verify soft delete settings
az storage account blob-service-properties show \
  --account-name "$PRIMARY" \
  --resource-group "$RG" \
  --query "{BlobSoftDelete:deleteRetentionPolicy, ContainerSoftDelete:containerDeleteRetentionPolicy, Versioning:isVersioningEnabled}" \
  -o json

# Verify network rules
az storage account show \
  --name "$PRIMARY" \
  --resource-group "$RG" \
  --query "networkRuleSet.{DefaultAction:defaultAction, Bypass:bypass, VNetRules:virtualNetworkRules[].id}" \
  -o json
```

## 🔑 SAS Token Exercises

```bash
PRIMARY=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labpri')].name" -o tsv)

# Generate an account-level SAS token (read/write/list, 1 hour expiry)
END=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%MZ' 2>/dev/null \
  || date -u -v+1H '+%Y-%m-%dT%H:%MZ')  # Linux || macOS

az storage account generate-sas \
  --account-name "$PRIMARY" \
  --permissions rwdlacup \
  --resource-types sco \
  --services b \
  --expiry "$END" \
  --https-only \
  -o tsv

# Generate a service-level SAS for a specific container
az storage container generate-sas \
  --account-name "$PRIMARY" \
  --name az104-lab-data \
  --permissions rl \
  --expiry "$END" \
  --auth-mode key \
  -o tsv

# Upload a test blob using the SAS token
echo "Hello AZ-104" > testblob.txt
az storage blob upload \
  --account-name "$PRIMARY" \
  --container-name az104-lab-data \
  --name testblob.txt \
  --file testblob.txt \
  --auth-mode login
rm testblob.txt

# Create a stored access policy (exam topic!)
az storage container policy create \
  --account-name "$PRIMARY" \
  --container-name az104-lab-data \
  --name readpolicy \
  --permissions rl \
  --expiry "$END"

# Generate SAS from stored access policy
az storage container generate-sas \
  --account-name "$PRIMARY" \
  --name az104-lab-data \
  --policy-name readpolicy \
  -o tsv
```

## 📦 AzCopy Examples

```bash
PRIMARY=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labpri')].name" -o tsv)
REPLICA=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labrep')].name" -o tsv)

# Login to AzCopy with Entra ID
azcopy login

# Upload a file to blob storage
echo "AzCopy demo file" > azcopy-demo.txt
azcopy copy 'azcopy-demo.txt' \
  "https://${PRIMARY}.blob.core.windows.net/az104-lab-data/azcopy-demo.txt"

# Copy between storage accounts (server-side copy)
azcopy copy \
  "https://${PRIMARY}.blob.core.windows.net/az104-lab-data/*" \
  "https://${REPLICA}.blob.core.windows.net/az104-lab-data-replica/" \
  --recursive

# Sync a local directory to a container
mkdir -p sync-demo && echo "file1" > sync-demo/a.txt && echo "file2" > sync-demo/b.txt
azcopy sync './sync-demo' \
  "https://${PRIMARY}.blob.core.windows.net/az104-lab-data/sync-demo" \
  --recursive

# List blobs in a container
azcopy list "https://${PRIMARY}.blob.core.windows.net/az104-lab-data"

# Clean up local files
rm -rf azcopy-demo.txt sync-demo
```

> **Exam tip:** AzCopy `copy` always transfers all files. `sync` only transfers files that differ (based on last-modified time or MD5 hash). Know the difference!

## 🔐 Encryption Notes

- **Microsoft-managed keys (MMK):** Enabled by default; no configuration needed.
- **Customer-managed keys (CMK):** Requires Azure Key Vault. Configure via:
  ```bash
  az storage account update \
    --name "$PRIMARY" \
    --resource-group "$RG" \
    --encryption-key-source Microsoft.Keyvault \
    --encryption-key-vault <vault-uri> \
    --encryption-key-name <key-name>
  ```
- **Infrastructure encryption (double encryption):** Must be set at account creation; cannot be changed later.
- All data is encrypted at rest (256-bit AES). Encryption in transit enforced by `minimumTlsVersion: TLS1_2`.

## 🧹 Clean Up

```bash
RG="rg-az104-lab-eastus"

# Delete just the storage accounts (preserve other lab resources)
PRIMARY=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labpri')].name" -o tsv)
REPLICA=$(az storage account list --resource-group "$RG" \
  --query "[?contains(name,'az104-labrep')].name" -o tsv)

az storage account delete --name "$PRIMARY" --resource-group "$RG" --yes
az storage account delete --name "$REPLICA" --resource-group "$RG" --yes

# Or delete the entire resource group (removes everything)
# az group delete --name "$RG" --yes --no-wait
```

## 📝 AZ-104 Exam Relevance

- **Configure access to storage:** Storage firewalls, VNet service endpoints, SAS tokens (account vs service vs user-delegation), stored access policies, access keys, Entra ID RBAC (Storage Blob Data Reader/Contributor/Owner roles)
- **Configure storage accounts:** Account types (StorageV2 vs BlobStorage), performance tiers (Standard vs Premium), replication options, access tiers, custom domains
- **Configure Azure Files:** SMB/NFS shares, snapshots, Azure File Sync, identity-based authentication (AD DS, Entra Domain Services)
- **Configure Azure Blob Storage:** Containers, access levels (private/blob/container), soft delete, versioning, change feed, point-in-time restore, immutability policies
- **Lifecycle management:** Tier transitions (Hot → Cool → Cold → Archive), automatic deletion, filtering by prefix and blob type
- **Object replication:** Cross-account async blob replication, requires versioning and change feed
- **Tools:** Storage Explorer (GUI), AzCopy (CLI bulk transfers), `az storage` commands
