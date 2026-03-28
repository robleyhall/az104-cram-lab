# Module 08: Monitoring & Backup

Azure Monitor, Log Analytics, alerts, Network Watcher, and Recovery Services — covering **10–15 % of the AZ-104 exam**.

> **Cram Video:** [John Savill's AZ-104 Cram Session](https://www.youtube.com/watch?v=0Knf9nub4-k)
>
> | Topic | Timestamp |
> |-------|-----------|
> | Monitoring | [3:45:25](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13525s) |
> | Alerting | [3:50:48](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13848s) |
> | Log Analytics | [3:54:57](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14097s) |
> | Network Watcher | [3:59:05](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14345s) |

## Learning Objectives

After completing this module you will be able to:

- Configure **Azure Monitor metrics** and understand platform vs. guest metrics
- Create a **Log Analytics workspace** and configure data sources
- Write and run **KQL (Kusto Query Language)** queries against log data
- Set up **metric alerts** and **log-based (scheduled query) alerts**
- Create **action groups** with email, SMS, webhook, and automation receivers
- Monitor **VMs** (CPU, memory, disk, heartbeat), **storage accounts**, and **networks**
- Use **Network Watcher** tools: IP Flow Verify, Next Hop, Connection Troubleshoot, NSG Flow Logs
- Deploy a **Recovery Services vault** and configure **VM backup policies**
- Perform **backup and restore** operations on Azure VMs
- Understand **Azure Site Recovery** concepts (failover/failback — conceptual in this lab)

## Azure Monitor Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                             │
│  VMs (agent)  │  Storage  │  Network  │  Azure AD  │  Activity │
└──────┬────────┴─────┬─────┴─────┬─────┴──────┬─────┴─────┬─────┘
       │              │           │            │           │
       ▼              ▼           ▼            ▼           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AZURE MONITOR                              │
│  ┌──────────────┐                    ┌────────────────────┐     │
│  │   Metrics     │  (numeric, near   │   Logs             │     │
│  │   (time-series)│  real-time,       │   (structured,     │     │
│  │               │  93-day default)  │   queryable via    │     │
│  │               │                   │   KQL, custom      │     │
│  │               │                   │   retention)       │     │
│  └──────┬───────┘                    └──────┬─────────────┘     │
│         │                                    │                  │
│  ┌──────▼──────────────────────────────────▼─────────────┐     │
│  │  Alerts  │  Dashboards  │  Workbooks  │  Autoscale    │     │
│  └──────────┴──────────────┴─────────────┴───────────────┘     │
│         │                                                       │
│  ┌──────▼───────────┐                                          │
│  │  Action Groups    │ → Email, SMS, Webhook, Logic App,       │
│  │                   │   Azure Function, ITSM, Runbook         │
│  └───────────────────┘                                          │
└─────────────────────────────────────────────────────────────────┘
```

**Metrics vs. Logs:**

| | Metrics | Logs |
|---|---------|------|
| Data type | Numeric time-series | Structured text/JSON |
| Latency | Near real-time (1 min) | Minutes (ingestion delay) |
| Retention | 93 days (platform) | 30 days free, up to 730 days |
| Query language | Metrics Explorer | KQL in Log Analytics |
| Cost | Free (platform metrics) | Per-GB ingestion |
| Alert type | Metric alert | Scheduled query rule |

## What Gets Deployed

| Resource | Name | Purpose |
|----------|------|---------|
| Log Analytics Workspace | `law-az104-lab-monitor` | Central log collection (PerGB2018, 30-day retention) |
| Diagnostic Setting | `diag-law-self` | Meta-monitoring: workspace logs sent to itself |
| Action Group | `ag-az104-lab-alerts` | Email notification target for alert rules |
| Metric Alert | `alert-az104-lab-vm-cpu` | VM CPU > 80 % over 5 min (conditional on vmResourceId) |
| Scheduled Query Alert | `alert-az104-lab-heartbeat` | VMs missing heartbeats for > 5 min |
| Recovery Services Vault | `rsv-az104-lab-backup` | VM backup management (LRS, soft delete enabled) |
| Backup Policy | `policy-az104-lab-vm-daily` | Daily backup at 02:00 UTC, 7 daily + 4 weekly retention |

All resources are tagged with `Environment=az104-lab`, `Project=az104-lab`, `Module=monitoring`.

> **Network Watcher** is auto-provisioned by Azure in each region when virtual network resources are created. It appears in the `NetworkWatcherRG` resource group. This module does not deploy it explicitly — see the [Network Watcher](#network-watcher) section below for hands-on exercises.

## Prerequisites

- **Module 07 deployed** — provides the VM resource ID for metric alerts and backup exercises
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (v2.60+)
- [Bicep CLI](https://learn.microsoft.com/azure/azure-resource-manager/bicep/install) (bundled with Azure CLI)

```bash
az --version
az bicep version
```

## Deploy

```bash
# 1. Create the resource group
az group create --name rg-az104-lab-monitor --location eastus

# 2. Preview changes (always do this first!)
az deployment group create \
  --resource-group rg-az104-lab-monitor \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --what-if

# 3. Deploy (without VM metric alert — uses default empty vmResourceId)
az deployment group create \
  --resource-group rg-az104-lab-monitor \
  --template-file main.bicep \
  --parameters main.bicepparam

# 4. (Optional) Deploy WITH the VM metric alert
#    Replace the resource ID with your Module 07 VM:
az deployment group create \
  --resource-group rg-az104-lab-monitor \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters vmResourceId='/subscriptions/<SUB_ID>/resourceGroups/rg-az104-lab-compute/providers/Microsoft.Compute/virtualMachines/vm-az104-lab-linux'
```

## Verify

```bash
# Confirm Log Analytics workspace
az monitor log-analytics workspace show \
  --resource-group rg-az104-lab-monitor \
  --workspace-name law-az104-lab-monitor \
  --query '{name:name, sku:sku.name, retention:retentionInDays, customerId:customerId}' \
  --output table

# List alert rules
az monitor metrics alert list \
  --resource-group rg-az104-lab-monitor \
  --output table

az monitor scheduled-query list \
  --resource-group rg-az104-lab-monitor \
  --output table

# Confirm Recovery Services vault
az backup vault show \
  --resource-group rg-az104-lab-monitor \
  --name rsv-az104-lab-backup \
  --query '{name:name, provisioningState:properties.provisioningState}' \
  --output table

# List backup policies
az backup policy list \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --output table

# Confirm action group
az monitor action-group show \
  --resource-group rg-az104-lab-monitor \
  --name ag-az104-lab-alerts \
  --query '{name:name, enabled:enabled, emailReceivers:emailReceivers[].emailAddress}' \
  --output json

# Verify Network Watcher exists in your region
az network watcher list --output table
```

## KQL Query Practice

The file `sample-kql-queries.txt` contains 10 exam-relevant queries. To run them:

1. Open the [Azure Portal](https://portal.azure.com)
2. Navigate to **Log Analytics workspaces** → `law-az104-lab-monitor` → **Logs**
3. Paste a query and click **Run**

Key KQL operators for the AZ-104 exam:

| Operator | Purpose | Example |
|----------|---------|---------|
| `where` | Filter rows | `where TimeGenerated > ago(1h)` |
| `summarize` | Aggregate | `summarize count() by Computer` |
| `project` | Select columns | `project TimeGenerated, Computer` |
| `order by` | Sort results | `order by AvgCPU desc` |
| `top` | Limit + sort | `top 10 by AvgCPU desc` |
| `ago()` | Relative time | `ago(5m)`, `ago(1h)`, `ago(7d)` |
| `count()` | Count rows | `summarize count() by Status` |
| `avg()` | Average | `summarize avg(CounterValue) by Computer` |
| `max()` / `min()` | Extremes | `summarize max(TimeGenerated) by Computer` |
| `extend` | Add calculated column | `extend SizeGB = SizeMB / 1024` |

## Enable VM Diagnostics

After deploying Module 07's VM, install the Azure Monitor Agent and send data to the workspace:

```bash
# Get the workspace ID and key
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-az104-lab-monitor \
  --workspace-name law-az104-lab-monitor \
  --query customerId -o tsv)

WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group rg-az104-lab-monitor \
  --workspace-name law-az104-lab-monitor \
  --query primarySharedKey -o tsv)

# Install Azure Monitor Agent on a Linux VM (recommended approach)
az vm extension set \
  --resource-group rg-az104-lab-compute \
  --vm-name vm-az104-lab-linux \
  --name AzureMonitorLinuxAgent \
  --publisher Microsoft.Azure.Monitor \
  --version 1.0 \
  --enable-auto-upgrade true

# Create a Data Collection Rule to send performance and syslog data
az monitor data-collection rule create \
  --resource-group rg-az104-lab-monitor \
  --name dcr-az104-lab-vm \
  --location eastus \
  --log-analytics "workspaceResourceId=$(az monitor log-analytics workspace show \
    --resource-group rg-az104-lab-monitor \
    --workspace-name law-az104-lab-monitor \
    --query id -o tsv)" \
  --performance-counters "streams=Microsoft-Perf samplingFrequencyInSeconds=60 \
    counterSpecifiers='\\Processor(_Total)\\% Processor Time' \
    counterSpecifiers='\\Memory\\Available MBytes'"

# Add diagnostic settings to a storage account (from Module 06)
az monitor diagnostic-settings create \
  --resource /subscriptions/<SUB_ID>/resourceGroups/rg-az104-lab-storage/providers/Microsoft.Storage/storageAccounts/<STORAGE_NAME>/blobServices/default \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group rg-az104-lab-monitor \
    --workspace-name law-az104-lab-monitor \
    --query id -o tsv) \
  --name diag-storage-to-law \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

## Configure VM Backup

```bash
# Enable backup for a VM using the policy from this module
az backup protection enable-for-vm \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --vm $(az vm show --resource-group rg-az104-lab-compute --name vm-az104-lab-linux --query id -o tsv) \
  --policy-name policy-az104-lab-vm-daily

# Trigger an on-demand backup (retain for 30 days)
az backup protection backup-now \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --container-name "IaasVMContainer;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --item-name "VM;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --retain-until $(date -u -d "+30 days" +%Y-%m-%dT%H:%M:%SZ) \
  --backup-management-type AzureIaasVM

# Check backup job status
az backup job list \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --output table

# Restore a VM (example — list recovery points first)
az backup recoverypoint list \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --container-name "IaasVMContainer;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --item-name "VM;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --output table
```

## Network Watcher

Network Watcher is auto-created in most regions. Use these tools for AZ-104 exam practice:

```bash
# Verify Network Watcher is active
az network watcher list --output table

# IP Flow Verify — check if traffic is allowed/denied by NSG
az network watcher test-ip-flow \
  --direction Inbound \
  --protocol TCP \
  --local 10.0.0.4:80 \
  --remote 203.0.113.5:12345 \
  --vm vm-az104-lab-linux \
  --resource-group rg-az104-lab-compute

# Next Hop — determine routing for a packet
az network watcher show-next-hop \
  --source-ip 10.0.0.4 \
  --dest-ip 10.1.0.4 \
  --vm vm-az104-lab-linux \
  --resource-group rg-az104-lab-compute

# Connection Troubleshoot — test TCP connectivity
az network watcher test-connectivity \
  --source-resource vm-az104-lab-linux \
  --source-resource-group rg-az104-lab-compute \
  --dest-address 10.1.0.4 \
  --dest-port 22

# Enable NSG Flow Logs (requires a storage account)
az network watcher flow-log create \
  --name flow-log-az104-lab \
  --nsg <NSG_RESOURCE_ID> \
  --storage-account <STORAGE_ACCOUNT_ID> \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group rg-az104-lab-monitor \
    --workspace-name law-az104-lab-monitor \
    --query id -o tsv) \
  --enabled true \
  --retention 7 \
  --traffic-analytics true
```

## Site Recovery (Conceptual)

Azure Site Recovery (ASR) provides disaster recovery by replicating VMs to a secondary region. The AZ-104 exam tests concepts but detailed implementation requires a paired-region setup beyond this lab's scope.

**Key concepts to know:**

- **Replication**: continuous replication of VMs to a target region
- **Recovery Plan**: defines failover order and automation steps
- **Failover**: switch workloads to the secondary region (planned or unplanned)
- **Failback**: return workloads to the primary region after recovery
- **RPO** (Recovery Point Objective): maximum acceptable data loss (time)
- **RTO** (Recovery Time Objective): maximum acceptable downtime
- **Test failover**: validates DR plan without impacting production

## AZ-104 Exam Relevance

This module covers concepts from the **Monitor and maintain Azure resources** domain:

- **Azure Monitor** — metrics, logs, data sources, and destinations
- **Log Analytics** — workspace creation, KQL queries, data retention
- **Alerts** — metric alerts, log alerts, action groups, severity levels
- **Diagnostic settings** — routing platform logs/metrics to Log Analytics, storage, or Event Hubs
- **Network Watcher** — IP Flow Verify, Next Hop, Connection Troubleshoot, NSG Flow Logs
- **Recovery Services vault** — backup vault creation, storage replication types
- **VM Backup** — backup policies, on-demand backup, restore operations
- **Site Recovery** — replication, failover, failback, RPO/RTO (conceptual)

## Knowledge Gaps & Further Study

| Topic | Why It Matters | Resource |
|-------|---------------|----------|
| Azure Backup vault vs. Recovery Services vault | Backup vault supports newer workloads (Blobs, Disks, PostgreSQL); RSV supports VMs, SQL, Files | [Compare vaults](https://learn.microsoft.com/azure/backup/backup-vault-overview) |
| Backup reports & monitoring | Configure vault diagnostics to Log Analytics for AddonAzureBackupJobs/Policy tables | [Backup reports](https://learn.microsoft.com/azure/backup/configure-reports) |
| Backup alerts & notifications | Built-in vs. custom alerts for backup failures | [Backup alerts](https://learn.microsoft.com/azure/backup/backup-azure-monitoring-built-in-monitor) |
| Site Recovery failover drill | Requires paired-region vault — practice in a test environment with GRS | [ASR tutorial](https://learn.microsoft.com/azure/site-recovery/azure-to-azure-tutorial-dr-drill) |
| Azure Monitor Agent vs. legacy MMA | AMA is the recommended agent; MMA is deprecated Aug 2024 | [AMA overview](https://learn.microsoft.com/azure/azure-monitor/agents/agents-overview) |
| Data Collection Rules (DCR) | Control what data the AMA collects and where it goes | [DCR overview](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview) |

## Clean Up

```bash
# Remove all monitoring resources
az group delete --name rg-az104-lab-monitor --yes --no-wait

# If you enabled backup on a VM, stop protection first:
az backup protection disable \
  --resource-group rg-az104-lab-monitor \
  --vault-name rsv-az104-lab-backup \
  --container-name "IaasVMContainer;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --item-name "VM;iaasvmcontainerv2;rg-az104-lab-compute;vm-az104-lab-linux" \
  --delete-backup-data true \
  --yes

# Then delete the resource group
az group delete --name rg-az104-lab-monitor --yes --no-wait
```

> **Note:** Recovery Services vaults with soft delete enabled will retain deleted backup data for 14 days. The vault cannot be fully deleted until soft-deleted items expire or are purged.
