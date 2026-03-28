// ============================================================================
// Module 08: Monitoring & Backup
// AZ-104 Certification Lab — Azure Monitor, Log Analytics, Alerts, Backup
// ============================================================================
// This module deploys a complete monitoring and backup stack: a Log Analytics
// workspace for centralised log collection, metric and log-based alerts,
// a Recovery Services vault with a daily VM backup policy, and diagnostic
// settings. Covers 10-15 % of the AZ-104 exam.
// ============================================================================

// --- Parameters ---

@description('Azure region for all resources. AZ-104 tests knowledge of region pairs — Recovery Services vaults replicate within a geo.')
param location string = 'eastus'

@description('Email address that receives alert notifications. Action Groups can also target SMS, webhook, ITSM, Logic Apps, and Azure Functions.')
param contactEmail string

@description('''
Resource ID of a VM to monitor with metric alerts (from Module 07).
Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{name}
Leave empty to skip the VM CPU metric alert.
''')
param vmResourceId string = ''

@description('Environment tag applied to every resource. Useful for cost tracking and policy enforcement — both AZ-104 topics.')
param environment string = 'az104-lab'

// --- Variables ---

@description('Standard tags applied to every resource in this module for consistent governance.')
var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'monitoring'
}

@description('Log Analytics workspace name. Central sink for logs from VMs, storage accounts, NSGs, and Azure AD.')
var workspaceName = 'law-az104-lab-monitor'

@description('Action group name. Action groups decouple "who to notify" from "what to alert on".')
var actionGroupName = 'ag-az104-lab-alerts'

@description('Recovery Services vault name. Manages backup and (optionally) Site Recovery for VMs.')
var vaultName = 'rsv-az104-lab-backup'

@description('Backup policy name. Defines schedule and retention — exam frequently tests retention rules.')
var backupPolicyName = 'policy-az104-lab-vm-daily'

// --- Log Analytics Workspace ---

@description('''
Log Analytics workspace — the central data store for Azure Monitor Logs.
AZ-104 key concepts:
  - PerGB2018 SKU = pay-as-you-go pricing with 5 GB/month free ingestion
  - Retention default is 30 days (free); up to 730 days at extra cost
  - Data sources: VM agents, diagnostic settings, Activity Log, Azure AD
  - Queried using Kusto Query Language (KQL)
''')
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// --- Diagnostic Setting on the Workspace (meta-monitoring) ---

@description('''
Diagnostic setting on the Log Analytics workspace itself — sends its own audit
and operational logs back into the workspace. This demonstrates the diagnostic
settings concept that the AZ-104 exam tests heavily. In production you would
also add diagnostic settings to VMs, storage accounts, Key Vaults, NSGs, etc.

Post-deployment, enable diagnostics on other resources via CLI:
  az monitor diagnostic-settings create \
    --resource <RESOURCE_ID> \
    --workspace <WORKSPACE_ID> \
    --name diag-to-law \
    --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]'
''')
resource workspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-law-self'
  scope: workspace
  properties: {
    workspaceId: workspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// --- Action Group ---

@description('''
Action group that defines notification targets for alerts.
AZ-104 exam concepts:
  - Short name ≤ 12 characters (used in SMS sender ID)
  - Receivers: email, SMS, push, voice, webhook, ITSM, Logic App, Azure Function, Automation Runbook
  - A single action group can be shared across many alert rules
  - Enabled/disabled flag lets you suppress during maintenance windows
''')
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global' // Action groups are always global
  tags: commonTags
  properties: {
    groupShortName: 'az104-labalrt'
    enabled: true
    emailReceivers: [
      {
        name: 'CertLabAdmin'
        emailAddress: contactEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// --- Metric Alert: VM CPU > 80 % ---

@description('''
Metric alert that fires when average CPU exceeds 80 % over a 5-minute window.
AZ-104 key concepts:
  - Metric alerts evaluate platform metrics (no agent required for host metrics)
  - Severity levels: 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose
  - Evaluation frequency vs. aggregation window — both tested on exam
  - Scopes: can target a single resource or multiple resources of same type
Conditionally deployed only when vmResourceId is provided.
''')
resource vmCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (!empty(vmResourceId)) {
  name: 'alert-az104-lab-vm-cpu'
  location: 'global' // Metric alerts are always global
  tags: commonTags
  properties: {
    description: 'Fires when average VM CPU exceeds 80% over 5 minutes'
    severity: 2 // Warning
    enabled: true
    scopes: [
      vmResourceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// --- Scheduled Query Rule Alert: Heartbeat ---

@description('''
Log-based (scheduled query) alert that detects VMs that stopped sending heartbeats.
AZ-104 key concepts:
  - Scheduled query rules run a KQL query on a schedule
  - Different from metric alerts: evaluates log data, not platform metrics
  - Requires the VM agent (Azure Monitor Agent or legacy MMA) to send Heartbeat data
  - Frequency and time window are independent settings
  - Result count vs. metric measurement alert types

NOTE: This alert will only fire meaningfully once VMs have the Azure Monitor Agent
installed and are sending Heartbeat data to this workspace. Without agents, the
query returns no results and the alert remains inactive.
''')
resource heartbeatAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-az104-lab-heartbeat'
  location: location
  tags: commonTags
  properties: {
    displayName: 'VM Heartbeat Missing'
    description: 'Fires when any VM stops sending heartbeats for more than 5 minutes. Requires Azure Monitor Agent on target VMs.'
    severity: 1 // Error
    enabled: true
    scopes: [
      workspace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'Heartbeat | summarize LastCall = max(TimeGenerated) by Computer | where LastCall < ago(5m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// --- Recovery Services Vault ---

@description('''
Recovery Services vault — the management entity for Azure Backup and Site Recovery.
AZ-104 key concepts:
  - Stores backup data (recovery points) for VMs, SQL, Files, Blobs
  - SKU: Standard (required for most backup scenarios)
  - Soft delete: keeps deleted backup data for 14 extra days (enabled by default)
  - Storage replication: LRS (cheapest), GRS (cross-region), ZRS (zone-redundant)
  - Recovery Services vault vs. Backup vault — RSV supports VMs; Backup vault is for newer workloads (PostgreSQL, Blobs, Disks)
  - Cross-Region Restore requires GRS
''')
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
    }
  }
}

// --- Vault Storage Replication Config ---

@description('''
Sets the vault storage replication type to Locally Redundant (LRS) for cost savings.
In production, use GeoRedundant (GRS) for cross-region protection.
AZ-104 tests the difference between LRS, GRS, and ZRS for vault storage.
Must be configured before registering any backup items.
''')
resource vaultStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2024-04-01' = {
  name: 'vaultstorageconfig'
  parent: recoveryVault
  properties: {
    storageModelType: 'LocallyRedundant'
    crossRegionRestoreFlag: false
  }
}

// --- Backup Policy: Daily VM Backup ---

@description('''
VM backup policy defining schedule and retention.
AZ-104 key concepts:
  - Schedule: daily, weekly, or custom
  - Retention: daily, weekly, monthly, yearly recovery points
  - Instant Restore: keeps snapshot locally for fast restores (1-5 days)
  - Application-consistent vs. crash-consistent snapshots
  - Backup window: typically overnight to reduce VM performance impact
  - Policy must exist before protecting (associating) a VM
''')
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  name: backupPolicyName
  parent: recoveryVault
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2024-01-01T02:00:00Z' // 2:00 AM UTC daily
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 7
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 4
          durationType: 'Weeks'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// --- Network Watcher ---
// Network Watcher is auto-provisioned by Azure in each region when you create
// or manage virtual network resources. It appears in a hidden resource group
// named 'NetworkWatcherRG'. You generally do NOT need to deploy it explicitly.
//
// AZ-104 Network Watcher capabilities to know:
//   - IP Flow Verify: test if a packet is allowed/denied by NSG rules
//   - Next Hop: determine the next hop for a packet from a VM
//   - Connection Troubleshoot: test TCP connectivity between resources
//   - NSG Flow Logs: capture network traffic metadata (requires storage account)
//   - Packet Capture: capture packets on a VM NIC (requires agent)
//   - Topology: visualise network resource relationships
//   - Connection Monitor: continuous connectivity monitoring
//
// To verify Network Watcher exists:
//   az network watcher list --output table

// --- Outputs ---

@description('Resource ID of the Log Analytics workspace. Use this to add diagnostic settings to other resources.')
output workspaceId string = workspace.id

@description('Workspace customer ID (GUID). Agents use this to identify which workspace to send data to.')
output workspaceCustomerId string = workspace.properties.customerId

@description('Resource ID of the Recovery Services vault. Use this when registering VMs for backup.')
output recoveryVaultId string = recoveryVault.id

@description('Name of the backup policy. Use this when enabling backup protection on VMs.')
output backupPolicyName string = backupPolicy.name

@description('Resource ID of the action group. Reuse this in additional alert rules.')
output actionGroupId string = actionGroup.id
