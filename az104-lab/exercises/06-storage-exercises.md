# Exercise 06: Storage

[🎥 Cram Session: Storage (2:31:50–3:10:21)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9110s)

> **Exam Domain**: Implement and manage storage (15–20%)
>
> These exercises cover storage accounts, blob storage, lifecycle management, SAS tokens, network rules, object replication, and Azure Files.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- [AzCopy](https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10) installed
- Module 00 (Foundation) deployed

```bash
az group create --name rg-az104-lab-storage --location eastus \
  --tags Environment=az104-lab Module=storage
```

---

## Exercise 6.1: Create a Storage Account and Upload Blobs

**Difficulty**: 🟢 Guided

**Objectives**:
- Create a storage account with specific redundancy
- Create blob containers with different access levels
- Upload blobs using Azure CLI and AzCopy

[🎥 Storage Accounts (2:31:50)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9110s)

**Steps**:

1. Create a storage account:
   ```bash
   STORAGE_PRIMARY="staz104-lab$(date +%s | tail -c 9)"
   az storage account create \
     --name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --sku Standard_LRS \
     --kind StorageV2 \
     --location eastus \
     --access-tier Hot \
     --min-tls-version TLS1_2 \
     --allow-blob-public-access false \
     --tags Environment=az104-lab
   echo "Primary storage: $STORAGE_PRIMARY"
   ```

2. Create blob containers:
   ```bash
   # Private container (default — no anonymous access)
   az storage container create \
     --name documents \
     --account-name "$STORAGE_PRIMARY" \
     --auth-mode login

   # Container for logs
   az storage container create \
     --name logs \
     --account-name "$STORAGE_PRIMARY" \
     --auth-mode login

   # Container for archived data
   az storage container create \
     --name archive \
     --account-name "$STORAGE_PRIMARY" \
     --auth-mode login
   ```

3. Create sample files and upload via CLI:
   ```bash
   echo "Report for $(date +%Y-%m-%d)" > sample-report.txt
   echo '{"status":"healthy","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' > health-check.json

   az storage blob upload \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --name "reports/sample-report.txt" \
     --file sample-report.txt \
     --auth-mode login

   az storage blob upload \
     --account-name "$STORAGE_PRIMARY" \
     --container-name logs \
     --name "health/health-check.json" \
     --file health-check.json \
     --auth-mode login
   ```

4. Upload using AzCopy (if installed):
   ```bash
   # First, get a storage account key for AzCopy
   STORAGE_KEY=$(az storage account keys list \
     --account-name "$STORAGE_PRIMARY" \
     --query "[0].value" -o tsv)

   # Upload with AzCopy
   azcopy copy "sample-report.txt" \
     "https://${STORAGE_PRIMARY}.blob.core.windows.net/documents/azcopy-report.txt?$(az storage account generate-sas \
       --account-name "$STORAGE_PRIMARY" \
       --account-key "$STORAGE_KEY" \
       --permissions rwdlacup \
       --services b \
       --resource-types co \
       --expiry $(date -u -v+1H +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ) \
       -o tsv)" 2>/dev/null || echo "ℹ️ AzCopy not installed — CLI upload worked fine"
   ```

5. List blobs in the container:
   ```bash
   az storage blob list \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --auth-mode login \
     --query "[].{name:name, size:properties.contentLength, tier:properties.blobTier}" \
     --output table
   ```

**Success Criteria**:
- [ ] Storage account created with Standard_LRS, StorageV2, Hot tier
- [ ] Three containers created (documents, logs, archive)
- [ ] Blobs uploaded via both CLI and AzCopy
- [ ] You understand the container access levels (Private, Blob, Container)

> 💡 **Exam Tip**: **AzCopy vs Storage Explorer vs CLI** — know when to use each:
> - **AzCopy**: Best for bulk/large transfers, supports bandwidth throttling, resumable
> - **Azure Storage Explorer**: GUI tool, good for browsing and interactive work
> - **Azure CLI/PowerShell**: Scriptable, automation-friendly
> - **Azure Portal**: Quick uploads, small files
>
> [🎥 Storage Tools (2:42:07)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9727s)

---

## Exercise 6.2: Configure Blob Lifecycle Management

**Difficulty**: 🟢 Guided

**Objectives**:
- Create lifecycle management rules for automatic tiering
- Understand access tiers (Hot, Cool, Cold, Archive)
- Configure rules based on last modified or last accessed time

[🎥 Lifecycle Management (2:49:05)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10145s)

**Steps**:

1. Create a lifecycle management policy:
   ```bash
   cat > lifecycle-policy.json << 'EOF'
   {
     "rules": [
       {
         "enabled": true,
         "name": "move-to-cool-after-30-days",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": {
               "tierToCool": {
                 "daysAfterModificationGreaterThan": 30
               }
             }
           },
           "filters": {
             "blobTypes": ["blockBlob"],
             "prefixMatch": ["logs/"]
           }
         }
       },
       {
         "enabled": true,
         "name": "move-to-archive-after-90-days",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": {
               "tierToArchive": {
                 "daysAfterModificationGreaterThan": 90
               }
             }
           },
           "filters": {
             "blobTypes": ["blockBlob"],
             "prefixMatch": ["logs/"]
           }
         }
       },
       {
         "enabled": true,
         "name": "delete-old-logs-after-365-days",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": {
               "delete": {
                 "daysAfterModificationGreaterThan": 365
               }
             }
           },
           "filters": {
             "blobTypes": ["blockBlob"],
             "prefixMatch": ["logs/"]
           }
         }
       },
       {
         "enabled": true,
         "name": "delete-old-snapshots",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "snapshot": {
               "delete": {
                 "daysAfterCreationGreaterThan": 90
               }
             }
           },
           "filters": {
             "blobTypes": ["blockBlob"]
           }
         }
       }
     ]
   }
   EOF
   ```

2. Apply the lifecycle policy:
   ```bash
   az storage account management-policy create \
     --account-name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --policy @lifecycle-policy.json
   ```

3. Verify the policy:
   ```bash
   az storage account management-policy show \
     --account-name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --query "policy.rules[].{name:name, enabled:enabled, filters:definition.filters.prefixMatch}" \
     --output table
   ```

4. Manually change a blob's tier to see the effect:
   ```bash
   az storage blob set-tier \
     --account-name "$STORAGE_PRIMARY" \
     --container-name logs \
     --name "health/health-check.json" \
     --tier Cool \
     --auth-mode login
   ```

5. Check the blob's current tier:
   ```bash
   az storage blob show \
     --account-name "$STORAGE_PRIMARY" \
     --container-name logs \
     --name "health/health-check.json" \
     --auth-mode login \
     --query "{name:name, tier:properties.blobTier, lastModified:properties.lastModified}" \
     --output json
   ```

**Success Criteria**:
- [ ] Lifecycle policy has rules for Cool (30d), Archive (90d), Delete (365d)
- [ ] Snapshot cleanup rule deletes snapshots older than 90 days
- [ ] You can manually change a blob's tier
- [ ] You understand the tiering cost tradeoffs

> 💡 **Exam Tip**: Access tier costs:
> - **Hot**: Highest storage cost, lowest access cost — for frequently accessed data
> - **Cool**: Lower storage cost, higher access cost — min 30-day retention
> - **Cold**: Even lower storage, higher access — min 90-day retention
> - **Archive**: Lowest storage, highest access, **offline** — min 180-day retention, requires rehydration (hours)
>
> [🎥 Blob Tiering (2:44:20)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=9860s)

> ⚠️ **Common Mistake**: Archive tier blobs cannot be read directly — they must be **rehydrated** to Hot or Cool first, which can take up to 15 hours (Standard) or 1 hour (High Priority). The exam tests this heavily.

---

## Exercise 6.3: Generate and Use SAS Tokens

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Generate account-level and service-level SAS tokens
- Understand SAS token parameters (permissions, expiry, IP restrictions)
- Test access with SAS tokens

[🎥 Access (2:56:41)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10601s)

**Steps**:

1. Generate an account-level SAS token:
   ```bash
   STORAGE_KEY=$(az storage account keys list \
     --account-name "$STORAGE_PRIMARY" \
     --query "[0].value" -o tsv)

   ACCOUNT_SAS=$(az storage account generate-sas \
     --account-name "$STORAGE_PRIMARY" \
     --account-key "$STORAGE_KEY" \
     --permissions rl \
     --services b \
     --resource-types co \
     --expiry $(date -u -v+1H +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ) \
     --https-only \
     -o tsv)
   echo "Account SAS: ?${ACCOUNT_SAS}"
   ```

2. Generate a service-level (container) SAS token:
   ```bash
   CONTAINER_SAS=$(az storage container generate-sas \
     --account-name "$STORAGE_PRIMARY" \
     --name documents \
     --permissions rl \
     --expiry $(date -u -v+1H +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ) \
     --https-only \
     --account-key "$STORAGE_KEY" \
     -o tsv)
   echo "Container SAS: ?${CONTAINER_SAS}"
   ```

3. Generate a SAS with IP restriction:
   ```bash
   RESTRICTED_SAS=$(az storage container generate-sas \
     --account-name "$STORAGE_PRIMARY" \
     --name documents \
     --permissions rl \
     --expiry $(date -u -v+1H +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ) \
     --https-only \
     --ip "203.0.113.0-203.0.113.255" \
     --account-key "$STORAGE_KEY" \
     -o tsv)
   echo "IP-restricted SAS: ?${RESTRICTED_SAS}"
   ```

4. Test the SAS token by listing blobs:
   ```bash
   az storage blob list \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --sas-token "$CONTAINER_SAS" \
     --query "[].name" -o tsv
   ```

5. **Explore**: Try to upload with a read-only SAS (should fail):
   ```bash
   echo "test" > sas-test.txt
   az storage blob upload \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --name "sas-test.txt" \
     --file sas-test.txt \
     --sas-token "$CONTAINER_SAS" 2>&1 || echo "⛔ Upload denied — SAS only has read+list permissions"
   rm -f sas-test.txt
   ```

6. Create a stored access policy (for revocable SAS):
   ```bash
   az storage container policy create \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --name "read-policy" \
     --permissions rl \
     --expiry $(date -u -v+24H +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -d '+24 hours' +%Y-%m-%dT%H:%MZ) \
     --account-key "$STORAGE_KEY"

   # Generate SAS from the stored policy
   POLICY_SAS=$(az storage container generate-sas \
     --account-name "$STORAGE_PRIMARY" \
     --name documents \
     --policy-name "read-policy" \
     --account-key "$STORAGE_KEY" \
     -o tsv)
   echo "Policy-based SAS: ?${POLICY_SAS}"
   ```

**Success Criteria**:
- [ ] Account-level SAS generated with read-list permissions
- [ ] Service-level SAS generated for a specific container
- [ ] Read-only SAS correctly prevents write operations
- [ ] Stored access policy created (allows revoking SAS by modifying the policy)

> 💡 **Exam Tip**: Three types of SAS:
> - **User Delegation SAS**: Signed with Entra ID credentials — **most secure**, recommended
> - **Service SAS**: Signed with storage account key, scoped to one service
> - **Account SAS**: Signed with storage account key, can span services
>
> **Stored access policies** let you revoke SAS tokens without rotating the key. Without a policy, the only way to revoke a SAS is to rotate the storage account key.

> ⚠️ **Common Mistake**: SAS tokens that are too permissive or have no expiry. Always use **least privilege** permissions, short expiry, HTTPS-only, and IP restrictions when possible.

---

## Exercise 6.4: Configure Storage Network Rules

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Configure storage firewall (default deny)
- Add VNet rules and IP rules
- Test access restrictions

**Steps**:

1. Set the default network rule to Deny:
   ```bash
   az storage account update \
     --name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --default-action Deny
   ```

2. Add your current IP to the allow list:
   ```bash
   MY_IP=$(curl -s https://ifconfig.me)
   az storage account network-rule add \
     --account-name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --ip-address "$MY_IP"
   echo "Added IP: $MY_IP"
   ```

3. Verify the network rules:
   ```bash
   az storage account show \
     --name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --query "{default:networkRuleSet.defaultAction, ipRules:networkRuleSet.ipRules[].ipAddressOrRange, bypass:networkRuleSet.bypass}" \
     --output json
   ```

4. Note the "bypass" setting:
   ```bash
   # By default, Azure services are allowed to bypass the firewall
   az storage account show \
     --name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --query "networkRuleSet.bypass" -o tsv
   # Output: AzureServices
   ```

5. Test access after firewall is enabled:
   ```bash
   az storage blob list \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --auth-mode login \
     --query "[].name" -o tsv
   ```

**Success Criteria**:
- [ ] Default action is Deny
- [ ] Your IP is whitelisted
- [ ] You understand the "AzureServices" bypass and when to use it
- [ ] You can explain how network rules interact with SAS tokens

> 💡 **Exam Tip**: Storage firewall applies to **all** access methods (keys, SAS, Entra ID). Even with a valid SAS token, if the source IP is not allowed, access is denied. The "Trusted Azure Services" bypass allows services like Azure Backup, Azure Monitor, etc. to access storage regardless of firewall rules.

---

## Exercise 6.5: Set Up Object Replication

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Configure object replication between two storage accounts
- Understand replication requirements (versioning, change feed)
- Monitor replication status

[🎥 Object Replication (2:50:22)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10222s)

**Steps**:

1. Create a secondary storage account:
   ```bash
   STORAGE_SECONDARY="streplica$(date +%s | tail -c 9)"
   az storage account create \
     --name "$STORAGE_SECONDARY" \
     --resource-group rg-az104-lab-storage \
     --sku Standard_LRS \
     --kind StorageV2 \
     --location westus2 \
     --tags Environment=az104-lab Purpose=replication
   echo "Secondary storage: $STORAGE_SECONDARY"
   ```

2. Enable versioning and change feed on both accounts (required for replication):
   ```bash
   for acct in "$STORAGE_PRIMARY" "$STORAGE_SECONDARY"; do
     az storage account blob-service-properties update \
       --account-name "$acct" \
       --resource-group rg-az104-lab-storage \
       --enable-versioning true \
       --enable-change-feed true
   done
   ```

3. Create a matching container on the secondary account:
   ```bash
   az storage container create \
     --name documents \
     --account-name "$STORAGE_SECONDARY" \
     --auth-mode login
   ```

4. Create the replication policy:
   ```bash
   az storage account or-policy create \
     --account-name "$STORAGE_SECONDARY" \
     --resource-group rg-az104-lab-storage \
     --source-account "$STORAGE_PRIMARY" \
     --destination-account "$STORAGE_SECONDARY" \
     --source-container documents \
     --destination-container documents \
     --min-creation-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```

5. Verify the replication policy:
   ```bash
   az storage account or-policy list \
     --account-name "$STORAGE_SECONDARY" \
     --resource-group rg-az104-lab-storage \
     --output table
   ```

6. Upload a new blob to the source and check replication:
   ```bash
   echo "Replicated content $(date)" > repl-test.txt
   az storage blob upload \
     --account-name "$STORAGE_PRIMARY" \
     --container-name documents \
     --name "repl-test.txt" \
     --file repl-test.txt \
     --auth-mode login

   # Wait a moment and check the destination
   sleep 30
   az storage blob list \
     --account-name "$STORAGE_SECONDARY" \
     --container-name documents \
     --auth-mode login \
     --query "[].{name:name, replicationStatus:properties.objectReplicationSourceProperties}" \
     --output table
   ```

**Success Criteria**:
- [ ] Both accounts have versioning and change feed enabled
- [ ] Replication policy is configured from primary to secondary
- [ ] Newly uploaded blobs replicate to the secondary account
- [ ] You understand the prerequisites (versioning, change feed, same blob type)

> 💡 **Exam Tip**: Object replication requires: **versioning enabled** on both accounts, **change feed enabled** on source. It only replicates **block blobs**, not page blobs or append blobs. Replication is **asynchronous** — there's no SLA on replication time.

---

## Exercise 6.6: Create and Mount an Azure File Share

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create an Azure file share
- Set quota and tiers
- Mount the file share (conceptually or on a VM)

[🎥 Azure Files (2:52:45)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=10365s)

**Steps**:

1. Create a file share:
   ```bash
   az storage share-rm create \
     --name "fileshare-team" \
     --storage-account "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --quota 100 \
     --access-tier Hot
   ```

2. Create a directory structure:
   ```bash
   STORAGE_KEY=$(az storage account keys list \
     --account-name "$STORAGE_PRIMARY" --query "[0].value" -o tsv)

   az storage directory create \
     --share-name "fileshare-team" \
     --account-name "$STORAGE_PRIMARY" \
     --name "shared-documents" \
     --account-key "$STORAGE_KEY"

   az storage directory create \
     --share-name "fileshare-team" \
     --account-name "$STORAGE_PRIMARY" \
     --name "team-resources" \
     --account-key "$STORAGE_KEY"
   ```

3. Upload a file to the share:
   ```bash
   echo "Shared team document" > team-doc.txt
   az storage file upload \
     --share-name "fileshare-team" \
     --account-name "$STORAGE_PRIMARY" \
     --source team-doc.txt \
     --path "shared-documents/team-doc.txt" \
     --account-key "$STORAGE_KEY"
   ```

4. List files in the share:
   ```bash
   az storage file list \
     --share-name "fileshare-team" \
     --account-name "$STORAGE_PRIMARY" \
     --path "shared-documents" \
     --account-key "$STORAGE_KEY" \
     --query "[].name" -o tsv
   ```

5. Get the mount command (for Linux):
   ```bash
   echo "# Mount command for Linux:"
   echo "sudo mount -t cifs //${STORAGE_PRIMARY}.file.core.windows.net/fileshare-team /mnt/fileshare \\"
   echo "  -o vers=3.0,username=${STORAGE_PRIMARY},password=${STORAGE_KEY},dir_mode=0777,file_mode=0777,serverino"
   ```

6. Configure snapshot for the file share:
   ```bash
   az storage share snapshot \
     --name "fileshare-team" \
     --account-name "$STORAGE_PRIMARY" \
     --account-key "$STORAGE_KEY"
   ```

**Success Criteria**:
- [ ] File share created with 100 GB quota
- [ ] Directory structure and files uploaded
- [ ] You can generate the mount command for Linux or Windows
- [ ] You understand file share tiers (Hot, Cool, Transaction Optimized, Premium)

> 💡 **Exam Tip**: Azure Files supports **SMB** (445) and **NFS** (2049) protocols. SMB works with Windows, Linux, and macOS. NFS requires Premium tier. Port **445 must be open** — many ISPs block it, which is a common troubleshooting scenario on the exam. Use Azure File Sync to cache on-premises.

---

## Exercise 6.7: Design a Storage Strategy

**Difficulty**: 🔴 Challenge

**Scenario**:

> *"Your company stores 10 TB of application logs. Logs are accessed frequently for 7 days, occasionally for 30 days, and rarely after that, but must be retained for 1 year. Design the storage strategy including tiering, replication, lifecycle management, and access control."*

**Your Task**:

1. Design the lifecycle policy:

   | Age | Tier | Justification |
   |-----|------|---------------|
   | 0–7 days | Hot | Frequently accessed for debugging |
   | 8–30 days | Cool | Occasional access for analysis |
   | 31–90 days | Cold | Rare access, regulatory holds |
   | 91–365 days | Archive | Compliance retention only |
   | > 365 days | Delete | Retention period complete |

2. Implement the full lifecycle policy:
   ```bash
   cat > full-lifecycle-policy.json << 'EOF'
   {
     "rules": [
       {
         "enabled": true,
         "name": "tier-to-cool",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": { "tierToCool": { "daysAfterModificationGreaterThan": 7 } }
           },
           "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] }
         }
       },
       {
         "enabled": true,
         "name": "tier-to-cold",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": { "tierToCold": { "daysAfterModificationGreaterThan": 30 } }
           },
           "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] }
         }
       },
       {
         "enabled": true,
         "name": "tier-to-archive",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": { "tierToArchive": { "daysAfterModificationGreaterThan": 90 } }
           },
           "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] }
         }
       },
       {
         "enabled": true,
         "name": "delete-old-logs",
         "type": "Lifecycle",
         "definition": {
           "actions": {
             "baseBlob": { "delete": { "daysAfterModificationGreaterThan": 365 } }
           },
           "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] }
         }
       }
     ]
   }
   EOF

   az storage account management-policy create \
     --account-name "$STORAGE_PRIMARY" \
     --resource-group rg-az104-lab-storage \
     --policy @full-lifecycle-policy.json
   ```

3. Design the access control strategy:

   | Principal | Access Method | Permissions | Justification |
   |-----------|--------------|-------------|---------------|
   | Dev team | Entra ID RBAC | Storage Blob Data Reader | Read logs for debugging |
   | Log ingestion service | SAS token (stored access policy) | Write only | Automated log upload |
   | Compliance auditor | User Delegation SAS | Read only, time-limited | Quarterly audits |
   | Backup service | Trusted Azure Service | Full | Cross-region replication |

4. Design the redundancy strategy:

   ```
   Decision: GRS (Geo-Redundant Storage) or RA-GRS?
   
   For logs that must be retained for compliance:
   - Use RA-GRS for read access in secondary region
   - Ensures availability even during regional outages
   - Cost: ~2x LRS but provides geographic redundancy
   
   Alternative: LRS + Object Replication
   - Lower cost than GRS
   - More control over what gets replicated
   - But: manual failover vs automatic with GRS
   ```

5. **Answer these design questions**:
   - Why not use Premium storage for logs?
   - What happens if you need to access an archived blob urgently?
   - How would you handle the case where logs must be immutable (cannot be deleted or modified)?

**Success Criteria**:
- [ ] Complete lifecycle policy with 4 tiers + deletion
- [ ] Access control uses least privilege (RBAC, SAS, stored policies)
- [ ] Redundancy strategy matches compliance requirements
- [ ] You can explain immutability policies (legal hold, time-based retention)

> 💡 **Exam Tip**: Storage redundancy options:
> - **LRS**: 3 copies in one datacenter (11 nines durability)
> - **ZRS**: 3 copies across availability zones (12 nines)
> - **GRS**: LRS + async copy to paired region (16 nines)
> - **RA-GRS**: GRS + read access to secondary
> - **GZRS**: ZRS + async copy to paired region
> - **RA-GZRS**: GZRS + read access to secondary (most durable)
>
> The exam tests when to use each. Key: "read access during regional outage" = RA-GRS/RA-GZRS.

> ⚠️ **Common Mistake**: Confusing **soft delete** with **versioning**. Soft delete protects against accidental deletion (recoverable for N days). Versioning keeps previous versions of a blob when it's overwritten. Both can be enabled simultaneously and serve different purposes.

> 📖 **Deep Dive**: [Azure Storage Documentation](https://learn.microsoft.com/en-us/azure/storage/) | [Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/) | [Azure Storage Explorer](https://learn.microsoft.com/en-us/azure/vs-azure-tools-storage-manage-with-storage-explorer)

---

## Clean Up

```bash
# Remove replication policy
az storage account or-policy list \
  --account-name "$STORAGE_SECONDARY" \
  --resource-group rg-az104-lab-storage \
  --query "[].policyId" -o tsv | while read pid; do
    az storage account or-policy delete \
      --account-name "$STORAGE_SECONDARY" \
      --resource-group rg-az104-lab-storage \
      --policy-id "$pid" 2>/dev/null
done

# Remove local files
rm -f sample-report.txt health-check.json repl-test.txt team-doc.txt
rm -f lifecycle-policy.json full-lifecycle-policy.json

# Remove resource group (removes all storage accounts)
az group delete --name rg-az104-lab-storage --yes --no-wait

echo "✅ Storage lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| Access Tiers | Hot (frequent), Cool (30d min), Cold (90d min), Archive (180d min, offline) |
| SAS Types | User Delegation (Entra ID, most secure), Service (key, one service), Account (key, multi-service) |
| Redundancy | LRS, ZRS, GRS, RA-GRS, GZRS, RA-GZRS — know the durability nines |
| Object Replication | Requires versioning + change feed; async; block blobs only |
| Azure Files | SMB (port 445) or NFS (Premium only); supports snapshots and Azure File Sync |
| Lifecycle Management | Auto-tier and delete based on age; supports prefix filters |
| Soft Delete | Recoverable deletion; separate settings for blobs, containers, and file shares |
| Immutability | Legal hold (indefinite) and time-based retention (fixed period) |

---

*Previous: [Exercise 05 — Load Balancing](05-load-balancing-exercises.md) | Next: [Exercise 07 — Compute](07-compute-exercises.md)*
