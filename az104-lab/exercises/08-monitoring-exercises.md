# Exercise 08: Monitoring & Backup

[🎥 Cram Session: Monitoring (3:45:25–4:01:34)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13525s)

> **Exam Domain**: Monitor and maintain Azure resources (10–15%)
>
> These exercises cover Azure Monitor, Log Analytics (KQL), alerts, diagnostic settings, Network Watcher, and Azure Backup.

---

## Prerequisites

- An active Azure subscription with **Contributor** role
- Azure CLI v2.60+ authenticated (`az login`)
- Module 00 (Foundation) deployed
- A Log Analytics workspace (created in Exercise 8.1)
- At least one VM deployed (from Module 07, or create one here)

```bash
az group create --name rg-certlab-monitoring --location eastus \
  --tags Environment=certlab Module=monitoring
```

---

## Exercise 8.1: Write Basic KQL Queries in Log Analytics

**Difficulty**: 🟢 Guided

**Objectives**:
- Create a Log Analytics workspace
- Write basic KQL queries (where, project, summarize, ago)
- Query common tables (Heartbeat, Perf, AzureActivity)

[🎥 Log Analytics Workspace (3:54:57)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14097s)

**Steps**:

1. Create a Log Analytics workspace:
   ```bash
   az monitor log-analytics workspace create \
     --workspace-name law-certlab \
     --resource-group rg-certlab-monitoring \
     --location eastus \
     --retention-time 30 \
     --tags Environment=certlab
   ```

2. Get the workspace ID (for future queries):
   ```bash
   LAW_ID=$(az monitor log-analytics workspace show \
     --workspace-name law-certlab \
     --resource-group rg-certlab-monitoring \
     --query customerId -o tsv)
   echo "Workspace ID: $LAW_ID"
   ```

3. Practice KQL queries. Open the Azure Portal → Log Analytics → Logs, or use CLI:

   **Query 1: Basic filtering**
   ```kql
   // Find all heartbeats from the last hour
   Heartbeat
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, Computer, OSType, Version
   | take 10
   ```

   **Query 2: Aggregation**
   ```kql
   // Count heartbeats per computer in the last 24 hours
   Heartbeat
   | where TimeGenerated > ago(24h)
   | summarize HeartbeatCount = count() by Computer
   | order by HeartbeatCount desc
   ```

   **Query 3: Performance data**
   ```kql
   // Average CPU usage per VM in the last hour
   Perf
   | where TimeGenerated > ago(1h)
   | where ObjectName == "Processor" and CounterName == "% Processor Time"
   | summarize AvgCPU = avg(CounterValue) by Computer, bin(TimeGenerated, 5m)
   | order by TimeGenerated desc
   ```

   **Query 4: Azure Activity logs**
   ```kql
   // Find all failed operations in the last 7 days
   AzureActivity
   | where TimeGenerated > ago(7d)
   | where ActivityStatusValue == "Failed"
   | project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller
   | order by TimeGenerated desc
   | take 20
   ```

   **Query 5: Join tables**
   ```kql
   // Find VMs with high CPU that stopped sending heartbeats
   Perf
   | where TimeGenerated > ago(1h)
   | where ObjectName == "Processor" and CounterName == "% Processor Time"
   | summarize AvgCPU = avg(CounterValue) by Computer
   | where AvgCPU > 90
   | join kind=leftouter (
       Heartbeat
       | summarize LastHeartbeat = max(TimeGenerated) by Computer
   ) on Computer
   | project Computer, AvgCPU, LastHeartbeat
   ```

4. Run a query via CLI (if data exists):
   ```bash
   az monitor log-analytics query \
     --workspace "$LAW_ID" \
     --analytics-query "AzureActivity | where TimeGenerated > ago(7d) | summarize count() by OperationNameValue | top 10 by count_" \
     --output table 2>/dev/null || echo "ℹ️ No data yet — data takes time to populate in the workspace"
   ```

**Success Criteria**:
- [ ] Log Analytics workspace created with 30-day retention
- [ ] You can write KQL using `where`, `project`, `summarize`, `ago()`, `count()`, `avg()`
- [ ] You understand the common tables: Heartbeat, Perf, AzureActivity, Syslog, Event
- [ ] You can use `join` to correlate data across tables

> 💡 **Exam Tip**: KQL operators to know for the exam:
> - `where`: Filter rows
> - `project`: Select/rename columns
> - `summarize`: Aggregate (count, avg, sum, max, min)
> - `ago()`: Relative time (ago(1h), ago(7d))
> - `bin()`: Time bucketing (bin(TimeGenerated, 5m))
> - `order by`: Sort results
> - `join`: Combine tables
> - `extend`: Add computed columns
> - `render`: Visualize (timechart, barchart, piechart)
>
> The exam expects you to **read and interpret** KQL, not write complex queries from scratch.

---

## Exercise 8.2: Create an Alert Rule with Action Group

**Difficulty**: 🟢 Guided

**Objectives**:
- Create an action group with email notification
- Create a metric alert rule
- Understand alert severity levels

[🎥 Alerting (3:50:48)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13848s)

**Steps**:

1. Create an action group:
   ```bash
   az monitor action-group create \
     --name ag-certlab-ops \
     --resource-group rg-certlab-monitoring \
     --short-name CertLabOps \
     --action email ops-email admin@yourdomain.com \
     --tags Environment=certlab
   ```

2. Verify the action group:
   ```bash
   az monitor action-group show \
     --name ag-certlab-ops \
     --resource-group rg-certlab-monitoring \
     --query "{name:name, shortName:groupShortName, receivers:emailReceivers[].{name:name, email:emailAddress}}" \
     --output json
   ```

3. Create a metric alert for high CPU on any VM in the resource group:
   ```bash
   az monitor metrics alert create \
     --name "alert-high-cpu" \
     --resource-group rg-certlab-monitoring \
     --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-certlab-monitoring" \
     --condition "avg Percentage CPU > 80" \
     --window-size 5m \
     --evaluation-frequency 1m \
     --severity 2 \
     --action ag-certlab-ops \
     --description "Alert when average CPU exceeds 80% for 5 minutes" \
     --target-resource-type "Microsoft.Compute/virtualMachines" \
     --tags Environment=certlab
   ```

4. Create an activity log alert (for resource deletions):
   ```bash
   az monitor activity-log alert create \
     --name "alert-resource-delete" \
     --resource-group rg-certlab-monitoring \
     --action-group ag-certlab-ops \
     --condition category=Administrative operationName="Microsoft.Resources/subscriptions/resourceGroups/delete/action" \
     --description "Alert when a resource group is deleted" \
     --tags Environment=certlab
   ```

5. List all alerts:
   ```bash
   echo "=== Metric Alerts ==="
   az monitor metrics alert list \
     --resource-group rg-certlab-monitoring \
     --query "[].{name:name, severity:severity, enabled:enabled}" -o table

   echo "=== Activity Log Alerts ==="
   az monitor activity-log alert list \
     --resource-group rg-certlab-monitoring \
     --query "[].{name:name, enabled:enabled}" -o table
   ```

**Success Criteria**:
- [ ] Action group created with email receiver
- [ ] Metric alert triggers at 80% CPU with 5-minute window
- [ ] Activity log alert monitors resource group deletions
- [ ] You understand alert severity levels (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)

> 💡 **Exam Tip**: Alert severity levels:
> | Severity | Level | Use For |
> |----------|-------|---------|
> | Sev 0 | Critical | System down, data loss imminent |
> | Sev 1 | Error | Service degraded, action needed |
> | Sev 2 | Warning | Approaching thresholds |
> | Sev 3 | Informational | Notable events, no action |
> | Sev 4 | Verbose | Debug-level detail |
>
> **Alert processing rules** (formerly action rules) let you suppress or modify alert notifications during maintenance windows.

> ⚠️ **Common Mistake**: Creating alerts without action groups — the alert fires but nobody gets notified. Always associate an action group. Also, metric alerts have a **minimum evaluation frequency of 1 minute**.

---

## Exercise 8.3: Configure Diagnostic Settings for Resources

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Enable diagnostic settings to send data to Log Analytics
- Configure metrics and logs collection
- Understand the data flow: resource → diagnostic settings → destination

[🎥 Monitoring (3:45:25)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=13525s)

**Steps**:

1. Create a storage account to monitor:
   ```bash
   MONITOR_STORAGE="stmon$(date +%s | tail -c 9)"
   az storage account create \
     --name "$MONITOR_STORAGE" \
     --resource-group rg-certlab-monitoring \
     --sku Standard_LRS \
     --location eastus \
     --tags Environment=certlab
   ```

2. Enable diagnostic settings for the storage account:
   ```bash
   STORAGE_ID=$(az storage account show --name "$MONITOR_STORAGE" \
     --resource-group rg-certlab-monitoring --query id -o tsv)
   LAW_RESOURCE_ID=$(az monitor log-analytics workspace show \
     --workspace-name law-certlab --resource-group rg-certlab-monitoring \
     --query id -o tsv)

   az monitor diagnostic-settings create \
     --name "diag-storage" \
     --resource "$STORAGE_ID" \
     --workspace "$LAW_RESOURCE_ID" \
     --metrics '[{"category":"Transaction","enabled":true}]'
   ```

3. Enable diagnostic settings for the blob service:
   ```bash
   az monitor diagnostic-settings create \
     --name "diag-blob" \
     --resource "${STORAGE_ID}/blobServices/default" \
     --workspace "$LAW_RESOURCE_ID" \
     --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
     --metrics '[{"category":"Transaction","enabled":true}]'
   ```

4. Verify diagnostic settings:
   ```bash
   az monitor diagnostic-settings list \
     --resource "$STORAGE_ID" \
     --query "[].{name:name, workspace:workspaceId}" -o table
   ```

5. Enable VM diagnostics (if a VM exists):
   ```bash
   # If you have a VM from Module 07, enable diagnostics
   VM_ID=$(az vm show --name vm-web-01 --resource-group rg-certlab-compute \
     --query id -o tsv 2>/dev/null)

   if [ -n "$VM_ID" ]; then
     az monitor diagnostic-settings create \
       --name "diag-vm" \
       --resource "$VM_ID" \
       --workspace "$LAW_RESOURCE_ID" \
       --metrics '[{"category":"AllMetrics","enabled":true}]'
     echo "✅ VM diagnostics enabled"
   else
     echo "ℹ️ No VM found — deploy one from Module 07 to enable VM diagnostics"
   fi
   ```

**Success Criteria**:
- [ ] Diagnostic settings send storage metrics to Log Analytics
- [ ] Blob service logs (Read, Write, Delete) are captured
- [ ] You understand the three diagnostic destinations: Log Analytics, Storage Account, Event Hub
- [ ] You know: each resource can have multiple diagnostic settings sending to different destinations

> 💡 **Exam Tip**: Diagnostic settings have three possible destinations:
> - **Log Analytics workspace**: For querying with KQL, alerting
> - **Storage account**: For long-term archival, compliance
> - **Event Hub**: For streaming to third-party SIEM tools
>
> You can send to multiple destinations simultaneously. Platform metrics are collected automatically; **diagnostic settings** are needed for resource logs.

---

## Exercise 8.4: Use Network Watcher for Troubleshooting

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Use Network Watcher IP flow verify
- Use connection troubleshoot
- Understand Network Watcher capabilities

[🎥 Network Watcher (3:59:05)](https://www.youtube.com/watch?v=0Knf9nub4-k&t=14345s)

**Steps**:

1. Verify Network Watcher is enabled in your region:
   ```bash
   az network watcher list --query "[?location=='eastus'].{name:name, state:provisioningState}" -o table
   ```

2. Enable Network Watcher if not present:
   ```bash
   az network watcher configure --locations eastus --enabled true --resource-group NetworkWatcherRG
   ```

3. Use IP Flow Verify to test if traffic is allowed (requires a VM):
   ```bash
   # Test if SSH (port 22) is allowed to a VM
   VM_ID=$(az vm show --name vm-web-01 --resource-group rg-certlab-compute \
     --query id -o tsv 2>/dev/null)

   if [ -n "$VM_ID" ]; then
     NIC_ID=$(az vm show --name vm-web-01 --resource-group rg-certlab-compute \
       --query "networkProfile.networkInterfaces[0].id" -o tsv)
     VM_IP=$(az network nic show --ids "$NIC_ID" \
       --query "ipConfigurations[0].privateIpAddress" -o tsv)

     az network watcher test-ip-flow \
       --direction Inbound \
       --local "${VM_IP}:22" \
       --remote "10.0.0.1:*" \
       --protocol TCP \
       --vm "$VM_ID" \
       --output json
   else
     echo "ℹ️ No VM found — deploy one from Module 07 to test IP flow verify"
     echo "Example output:"
     echo '{"access": "Allow", "ruleName": "AllowSSH"}'
   fi
   ```

4. Use Connection Troubleshoot:
   ```bash
   if [ -n "$VM_ID" ]; then
     az network watcher test-connectivity \
       --source-resource "$VM_ID" \
       --dest-address "www.microsoft.com" \
       --dest-port 443 \
       --output json
   else
     echo "ℹ️ Connection troubleshoot requires a source VM"
     echo "It tests end-to-end connectivity including NSG rules, routing, and DNS"
   fi
   ```

5. View NSG flow logs configuration:
   ```bash
   az network watcher flow-log list \
     --location eastus \
     --query "[].{name:name, nsg:targetResourceId, enabled:enabled}" -o table 2>/dev/null \
     || echo "ℹ️ No flow logs configured yet"
   ```

6. **Explore**: List all Network Watcher capabilities:
   ```bash
   echo "Network Watcher capabilities:"
   echo "  • IP Flow Verify — check if traffic is allowed/denied by NSG"
   echo "  • Connection Troubleshoot — test end-to-end connectivity"
   echo "  • Next Hop — determine the next hop for a packet"
   echo "  • NSG Flow Logs — capture traffic data for analysis"
   echo "  • Packet Capture — capture packets on a VM"
   echo "  • Connection Monitor — continuous connectivity monitoring"
   echo "  • Topology — visualize network topology"
   ```

**Success Criteria**:
- [ ] Network Watcher is enabled in your region
- [ ] You understand IP Flow Verify (tests NSG rules for a specific flow)
- [ ] You understand Connection Troubleshoot (tests end-to-end connectivity)
- [ ] You can explain the difference between the two tools

> 💡 **Exam Tip**: Network Watcher tools:
> - **IP Flow Verify**: Tests if a specific packet is allowed/denied by **NSG rules**. Tells you which rule allowed/denied it.
> - **Connection Troubleshoot**: Tests **end-to-end** connectivity including routing, DNS, NSG, and firewalls.
> - **Next Hop**: Shows where a packet will be routed (system route or UDR).
> - **NSG Flow Logs**: Captures all traffic data — who connected to what, when, allowed/denied.
>
> The exam often presents a troubleshooting scenario and asks which Network Watcher tool to use.

---

## Exercise 8.5: Set Up VM Backup Policy

**Difficulty**: 🟡 Exploratory

**Objectives**:
- Create a Recovery Services vault
- Configure a backup policy with retention settings
- Enable backup for a VM

**Steps**:

1. Create a Recovery Services vault:
   ```bash
   az backup vault create \
     --name rsv-certlab \
     --resource-group rg-certlab-monitoring \
     --location eastus \
     --tags Environment=certlab
   ```

2. View the default backup policy:
   ```bash
   az backup policy list \
     --vault-name rsv-certlab \
     --resource-group rg-certlab-monitoring \
     --query "[].{name:name, type:properties.backupManagementType}" -o table
   ```

3. Create a custom backup policy:
   ```bash
   az backup policy set \
     --vault-name rsv-certlab \
     --resource-group rg-certlab-monitoring \
     --name "policy-daily-30d" \
     --policy '{
       "schedulePolicy": {
         "schedulePolicyType": "SimpleSchedulePolicy",
         "scheduleRunFrequency": "Daily",
         "scheduleRunTimes": ["2024-01-01T02:00:00Z"]
       },
       "retentionPolicy": {
         "retentionPolicyType": "LongTermRetentionPolicy",
         "dailySchedule": {
           "retentionTimes": ["2024-01-01T02:00:00Z"],
           "retentionDuration": { "count": 30, "durationType": "Days" }
         },
         "weeklySchedule": {
           "daysOfTheWeek": ["Sunday"],
           "retentionTimes": ["2024-01-01T02:00:00Z"],
           "retentionDuration": { "count": 12, "durationType": "Weeks" }
         }
       }
     }' 2>/dev/null || echo "ℹ️ Custom policy creation may require Portal for complex configurations"
   ```

4. Enable backup for a VM (if one exists):
   ```bash
   VM_EXISTS=$(az vm show --name vm-web-01 --resource-group rg-certlab-compute --query id -o tsv 2>/dev/null)

   if [ -n "$VM_EXISTS" ]; then
     az backup protection enable-for-vm \
       --vault-name rsv-certlab \
       --resource-group rg-certlab-monitoring \
       --vm vm-web-01 \
       --policy-name DefaultPolicy
     echo "✅ Backup enabled for vm-web-01"
   else
     echo "ℹ️ No VM found to protect. Deploy one from Module 07 first."
     echo "Command to enable backup:"
     echo "  az backup protection enable-for-vm --vault-name rsv-certlab --resource-group rg-certlab-monitoring --vm <vm-name> --policy-name DefaultPolicy"
   fi
   ```

5. Check backup status:
   ```bash
   az backup item list \
     --vault-name rsv-certlab \
     --resource-group rg-certlab-monitoring \
     --query "[].{name:name, status:properties.protectionState, lastBackup:properties.lastBackupTime}" \
     --output table 2>/dev/null || echo "ℹ️ No backup items configured yet"
   ```

6. Trigger an on-demand backup:
   ```bash
   if [ -n "$VM_EXISTS" ]; then
     az backup protection backup-now \
       --vault-name rsv-certlab \
       --resource-group rg-certlab-monitoring \
       --container-name "$(az backup container list --vault-name rsv-certlab --resource-group rg-certlab-monitoring --backup-management-type AzureIaasVM --query '[0].name' -o tsv 2>/dev/null)" \
       --item-name "$(az backup item list --vault-name rsv-certlab --resource-group rg-certlab-monitoring --query '[0].name' -o tsv 2>/dev/null)" \
       --retain-until "$(date -u -v+30d +%d-%m-%Y 2>/dev/null || date -u -d '+30 days' +%d-%m-%Y)" 2>/dev/null \
       && echo "✅ On-demand backup triggered" \
       || echo "ℹ️ On-demand backup requires an active protected item"
   fi
   ```

**Success Criteria**:
- [ ] Recovery Services vault created
- [ ] Default backup policy reviewed (daily backup, 30-day retention)
- [ ] Backup enabled for a VM (or you know the command to do so)
- [ ] You understand: Recovery Services vault vs Backup vault

> 💡 **Exam Tip**: **Recovery Services vault** vs **Backup vault**:
> - **Recovery Services vault**: VMs, SQL in Azure VM, Azure Files, SAP HANA — the classic vault
> - **Backup vault**: Azure Disks, Azure Blobs, Azure Database for PostgreSQL — newer vault type
>
> Key backup concepts: **RPO** (Recovery Point Objective) = max acceptable data loss time. **RTO** (Recovery Time Objective) = max acceptable downtime. The exam asks you to choose policies based on RPO/RTO requirements.

---

## Exercise 8.6: Create a Monitoring Dashboard

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a comprehensive monitoring dashboard
- Combine metrics and log queries
- Create a reusable dashboard definition

**Steps**:

1. Create a shared dashboard via CLI:
   ```bash
   az portal dashboard create \
     --name "dashboard-certlab-ops" \
     --resource-group rg-certlab-monitoring \
     --input-path /dev/stdin << 'EOF'
   {
     "lenses": {
       "0": {
         "order": 0,
         "parts": {
           "0": {
             "position": {"x": 0, "y": 0, "colSpan": 6, "rowSpan": 4},
             "metadata": {
               "type": "Extension/Microsoft_OperationsManagementSuite_Workspace/PartType/LogsDashboardPart",
               "inputs": [],
               "settings": {
                 "content": {
                   "Query": "Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)"
                 }
               }
             }
           }
         }
       }
     },
     "metadata": {
       "model": {
         "timeRange": {"value": {"relative": {"duration": 24, "timeUnit": 1}}},
         "filterLocale": {"value": "en-us"}
       }
     }
   }
   EOF
   echo "ℹ️ For best results, create dashboards in the Azure Portal with drag-and-drop"
   ```

2. Design your dashboard layout (implement in Portal):

   | Panel | Type | Query/Metric | Purpose |
   |-------|------|-------------|---------|
   | VM Health | KQL | `Heartbeat \| summarize by Computer` | Which VMs are reporting |
   | CPU Usage | Metric Chart | Percentage CPU by VM | Resource utilization |
   | Failed Operations | KQL | `AzureActivity \| where Status == "Failed"` | Error tracking |
   | Disk Space | KQL | `Perf \| where ObjectName == "LogicalDisk"` | Capacity planning |
   | Alert Summary | Alert widget | Active alerts by severity | At-a-glance health |
   | Network Traffic | Metric Chart | Network In/Out by NIC | Bandwidth monitoring |

3. Create KQL queries for each panel:
   ```kql
   // Panel 1: VM Health Status
   Heartbeat
   | summarize LastHeartbeat = max(TimeGenerated) by Computer, OSType
   | extend Status = iff(LastHeartbeat < ago(5m), "⚠️ Unhealthy", "✅ Healthy")
   | project Computer, OSType, LastHeartbeat, Status

   // Panel 2: Top 5 VMs by CPU (last hour)
   Perf
   | where TimeGenerated > ago(1h)
   | where ObjectName == "Processor" and CounterName == "% Processor Time"
   | summarize AvgCPU = avg(CounterValue) by Computer
   | top 5 by AvgCPU desc
   | render barchart

   // Panel 3: Failed Operations Timeline
   AzureActivity
   | where TimeGenerated > ago(24h)
   | where ActivityStatusValue == "Failed"
   | summarize FailCount = count() by bin(TimeGenerated, 1h)
   | render timechart

   // Panel 4: Available Disk Space
   Perf
   | where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
   | where InstanceName != "_Total"
   | summarize FreeSpace = avg(CounterValue) by Computer, InstanceName
   | where FreeSpace < 20
   | order by FreeSpace asc
   ```

**Success Criteria**:
- [ ] Dashboard design covers all key monitoring areas
- [ ] KQL queries are correct and meaningful
- [ ] You understand the difference between metric charts (real-time) and log queries (near real-time)
- [ ] Dashboard can be shared with team members

> 💡 **Exam Tip**: Azure Monitor data types:
> - **Metrics**: Numeric time-series data, collected at regular intervals, near real-time. Stored for 93 days.
> - **Logs**: Rich text/numeric data, stored in Log Analytics workspace, queried with KQL. Stored per retention policy.
>
> Metrics are great for dashboards and quick alerts. Logs are great for deep investigation and complex queries.

---

## Exercise 8.7: Design a Backup Strategy

**Difficulty**: 🔴 Challenge

**Objectives**:
- Design a backup strategy meeting specific RPO/RTO requirements
- Plan cross-region disaster recovery
- Consider cost optimization

**Scenario**:

> *"Your VM stopped responding at 3 AM. Using Azure Monitor and Log Analytics, describe the steps to diagnose the issue. Then design a backup strategy for VMs across two regions with RPO of 1 hour and RTO of 4 hours."*

**Part 1: Incident Diagnosis Runbook**

Document the steps you would take:

```
Step 1: Check VM status
  az vm get-instance-view --name <vm-name> --resource-group <rg> \
    --query "instanceView.statuses[1].displayStatus"

Step 2: Check recent alerts
  - Azure Portal → Monitor → Alerts → Filter by time range and resource

Step 3: Review Azure Activity Log
  AzureActivity
  | where TimeGenerated > ago(6h)
  | where _ResourceId contains "<vm-name>"
  | where ActivityStatusValue != "Succeeded"
  | project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller

Step 4: Check VM performance before the outage
  Perf
  | where TimeGenerated between(ago(6h) .. ago(2h))
  | where Computer == "<vm-name>"
  | where ObjectName == "Processor" or ObjectName == "Memory"
  | summarize avg(CounterValue) by CounterName, bin(TimeGenerated, 5m)
  | render timechart

Step 5: Check for disk space issues
  Perf
  | where Computer == "<vm-name>"
  | where ObjectName == "LogicalDisk" and CounterName == "% Free Space"
  | summarize min(CounterValue) by InstanceName, bin(TimeGenerated, 15m)

Step 6: Use Network Watcher Connection Troubleshoot
  az network watcher test-connectivity \
    --source-resource <vm-id> --dest-address <target> --dest-port 443

Step 7: Check boot diagnostics (if enabled)
  az vm boot-diagnostics get-boot-log --name <vm-name> --resource-group <rg>
```

**Part 2: Backup Strategy Design**

| Requirement | Solution |
|-------------|----------|
| **RPO: 1 hour** | Backup frequency: ____________ |
| **RTO: 4 hours** | Recovery method: ____________ |
| **Cross-region** | Replication strategy: ____________ |
| **Cost optimization** | Tiering: ____________ |

Design your strategy:

```
Primary Region (East US):
  - Recovery Services Vault: rsv-primary-eastus
  - Backup Policy: Every 4 hours (meets 1-hour RPO with margin)
  - Retention: 7 daily, 4 weekly, 12 monthly

Secondary Region (West US 2):
  - Azure Site Recovery (ASR) replication
  - Continuous replication of VM disks
  - Failover RTO: ~2-4 hours (meets 4-hour RTO)

  Alternative: Cross-Region Restore (CRR)
  - Enable CRR on Recovery Services vault
  - Restore from replicated backup data in secondary region
  - RTO depends on VM size and disk count
```

Implement the core components:
```bash
# Enable cross-region restore on the vault
az backup vault backup-properties set \
  --name rsv-certlab \
  --resource-group rg-certlab-monitoring \
  --cross-region-restore-flag true 2>/dev/null \
  || echo "ℹ️ CRR requires GRS redundancy on the vault"

# Check vault redundancy
az backup vault show \
  --name rsv-certlab \
  --resource-group rg-certlab-monitoring \
  --query "properties.storageType" 2>/dev/null
```

**Success Criteria**:
- [ ] Diagnosis runbook covers: VM status → Activity Log → Performance metrics → Network → Boot diagnostics
- [ ] Backup strategy meets RPO (1 hour) and RTO (4 hours)
- [ ] Cross-region DR plan uses ASR or CRR
- [ ] You can explain RPO vs RTO and how backup frequency affects RPO

> 💡 **Exam Tip**: **Azure Site Recovery** (ASR) vs **Azure Backup**:
> - **Backup**: Protects data — point-in-time recovery of individual VMs/files
> - **ASR**: Protects entire workloads — replicates VMs to a secondary region for disaster recovery
>
> For the lowest RTO, ASR is preferred (continuous replication, near-instant failover). For the lowest cost, Azure Backup with CRR is more economical but has higher RTO.
>
> The exam asks you to choose between Backup and ASR based on RPO/RTO requirements.

> ⚠️ **Common Mistake**: Confusing backup **retention** with backup **frequency**. Retention = how long you keep backups. Frequency = how often you take them. RPO depends on frequency, not retention.

> 📖 **Deep Dive**: [Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/) | [Network Watcher](https://learn.microsoft.com/en-us/azure/network-watcher/) | [Azure Backup](https://learn.microsoft.com/en-us/azure/backup/) | [Azure Site Recovery](https://learn.microsoft.com/en-us/azure/site-recovery/)

---

## Clean Up

```bash
# Disable backup protection (required before vault deletion)
az backup protection disable \
  --vault-name rsv-certlab \
  --resource-group rg-certlab-monitoring \
  --container-name "$(az backup container list --vault-name rsv-certlab --resource-group rg-certlab-monitoring --backup-management-type AzureIaasVM --query '[0].name' -o tsv 2>/dev/null)" \
  --item-name "$(az backup item list --vault-name rsv-certlab --resource-group rg-certlab-monitoring --query '[0].name' -o tsv 2>/dev/null)" \
  --delete-backup-data true --yes 2>/dev/null

# Delete Recovery Services vault
az backup vault delete --name rsv-certlab --resource-group rg-certlab-monitoring --yes --force 2>/dev/null

# Remove resource group
az group delete --name rg-certlab-monitoring --yes --no-wait

echo "✅ Monitoring & backup lab resources cleaned up"
```

---

## Key Concepts for the Exam

| Concept | Details |
|---------|---------|
| KQL Operators | `where`, `project`, `summarize`, `ago()`, `bin()`, `join`, `extend`, `render` |
| Alert Severity | 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose |
| Alert Types | Metric alerts (near real-time), Log alerts (KQL-based), Activity log alerts |
| Diagnostic Destinations | Log Analytics, Storage Account, Event Hub |
| Network Watcher | IP Flow Verify (NSG), Connection Troubleshoot (end-to-end), Next Hop (routing) |
| Backup vs ASR | Backup = data protection. ASR = workload replication for DR. |
| RPO vs RTO | RPO = max data loss time. RTO = max downtime. |
| Vault Types | Recovery Services vault (VMs, SQL) vs Backup vault (Disks, Blobs) |
| Metrics vs Logs | Metrics = numeric, real-time, 93-day retention. Logs = rich, KQL-queryable, configurable retention. |

---

*Previous: [Exercise 07 — Compute](07-compute-exercises.md)*
