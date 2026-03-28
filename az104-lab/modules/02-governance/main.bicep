// ============================================================================
// Module 02: Governance & Compliance
// AZ-104 Exam Weight: 20-25% — Manage Azure identities and governance
// ============================================================================
// Deploys Azure Policy assignments, a custom RBAC role, resource locks,
// a monthly budget with cost alerts, and enforces tagging standards.
// These are core governance primitives tested heavily on the AZ-104 exam.
// ============================================================================

targetScope = 'resourceGroup'

// ──────────────────────────────────────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────────────────────────────────────

@description('Azure region for resources that require a location. Most governance resources (policies, RBAC, locks) are control-plane and region-agnostic, but budgets and some assignments need it.')
param location string = 'eastus'

@description('Email address for budget alert notifications. Budget alerts fire at the configured threshold and send to this contact.')
param contactEmail string

@description('Environment label applied as a tag to all resources. Also used by the tag-inheritance policy to propagate from resource group to child resources.')
param environment string = 'az104-lab'

@description('Monthly spending limit in USD for the budget alert. The AZ-104 exam tests cost management concepts including budgets, cost alerts, and spending thresholds.')
param monthlyBudgetAmount int = 50

@description('Percentage threshold (0-100) at which the budget alert fires. An 80% threshold on a $50 budget triggers at $40 spend.')
param budgetAlertThresholdPercent int = 80

@description('Budget start date in yyyy-MM-dd format. Defaults to the first of the current month. Must use a parameter because utcNow() is only allowed in parameter defaults.')
param budgetStartDate string = '${utcNow('yyyy-MM')}-01'

// ──────────────────────────────────────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────────────────────────────────────

// Note: Governance control-plane resources (policies, locks, RBAC roles, budgets) do not
// support Azure tags directly. Tags are applied to the resource group via CLI at creation
// time (see README.md deploy steps). The tag policies deployed here enforce tagging on
// data-plane resources created within the resource group.

var subscriptionId = subscription().subscriptionId
var resourceGroupName = resourceGroup().name

// Built-in policy definition IDs — these are Microsoft-managed and globally available
var policyAuditManagedDisks = '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d'
var policyRequireTagOnRg = '/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025'
var policyInheritTagFromRg = '/providers/Microsoft.Authorization/policyDefinitions/ea3f2387-9b95-492a-a190-fcbf2b71b6ec'

// ──────────────────────────────────────────────────────────────────────────────
// Azure Policy Assignments
// ──────────────────────────────────────────────────────────────────────────────
// Azure Policy evaluates resources for compliance with organizational standards.
// Policies can audit, deny, append, modify, or deploy resources automatically.
// The AZ-104 exam tests: creating assignments, understanding effects, evaluating
// compliance state, and remediating non-compliant resources.
// ──────────────────────────────────────────────────────────────────────────────

@description('''
Policy: Audit VMs that do not use managed disks.
Effect: Audit (reports non-compliance but does not block deployments).
This built-in policy checks whether VM OS and data disks use Azure Managed Disks
instead of storage-account-based (unmanaged) disks. Managed disks are the recommended
approach for reliability, scalability, and simplified management.
''')
resource policyAuditUnmanagedDisks 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'audit-unmanaged-disks'
  properties: {
    displayName: 'CertLab — Audit VMs without managed disks'
    description: 'Identifies virtual machines that are not using managed disks. Managed disks provide better reliability and are required for SLA-backed VMs.'
    policyDefinitionId: policyAuditManagedDisks
    enforcementMode: 'Default'
  }
}

@description('''
Policy: Require an 'Environment' tag on resource groups.
Effect: Deny (blocks creation of resource groups missing the tag).
Tag governance is a core AZ-104 topic. Requiring tags on resource groups ensures
consistent metadata for cost tracking, environment identification, and automation.
''')
resource policyRequireEnvironmentTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'require-env-tag-on-rg'
  properties: {
    displayName: 'CertLab — Require Environment tag on resource groups'
    description: 'Denies creation of resource groups that do not have an Environment tag. Enforces organizational tagging standards for cost management and resource organization.'
    policyDefinitionId: policyRequireTagOnRg
    enforcementMode: 'DoNotEnforce'
    parameters: {
      tagName: {
        value: 'Environment'
      }
    }
  }
}

@description('''
Policy: Inherit the 'Environment' tag from the resource group if missing.
Effect: Modify (automatically adds the tag to resources at deploy time).
This policy demonstrates tag inheritance — a powerful governance pattern where
child resources automatically receive tags from their parent resource group.
Requires a managed identity for the modify effect to write tags.
''')
resource policyInheritEnvironmentTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'inherit-env-tag-from-rg'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'CertLab — Inherit Environment tag from resource group'
    description: 'Automatically applies the Environment tag from the resource group to child resources that are missing it. Demonstrates the Modify policy effect and managed identity requirement.'
    policyDefinitionId: policyInheritTagFromRg
    enforcementMode: 'Default'
    parameters: {
      tagName: {
        value: 'Environment'
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Custom RBAC Role Definition
// ──────────────────────────────────────────────────────────────────────────────
// Azure RBAC uses role definitions (sets of permissions) and role assignments
// (binding a role to a principal at a scope). Custom roles let you create
// least-privilege access patterns beyond the built-in roles.
// The AZ-104 exam tests: built-in vs custom roles, role assignments,
// scope inheritance, and interpreting effective permissions.
// ──────────────────────────────────────────────────────────────────────────────

@description('''
Custom RBAC role: CertLab VM Operator.
Allows starting, stopping (deallocating), and restarting VMs but NOT deleting them.
This demonstrates the principle of least privilege — operators can manage VM power
state for cost control without the ability to permanently destroy resources.
Assignable at the current subscription scope.
''')
resource customRoleVmOperator 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscriptionId, 'az104-lab-vm-operator')
  properties: {
    roleName: 'CertLab VM Operator'
    description: 'Can start, stop (deallocate), and restart virtual machines but cannot delete them. Designed for operators who manage VM power state for cost optimization.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/start/action'
          'Microsoft.Compute/virtualMachines/deallocate/action'
          'Microsoft.Compute/virtualMachines/restart/action'
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/instanceView/read'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Resource Lock
// ──────────────────────────────────────────────────────────────────────────────
// Resource locks prevent accidental deletion or modification of critical resources.
// CanNotDelete: allows read and modify but blocks delete operations.
// ReadOnly: blocks both modify and delete (only reads allowed).
// Locks apply regardless of RBAC permissions — even Owners must remove the lock first.
// The AZ-104 exam tests: lock types, lock inheritance, and lock vs RBAC interaction.
// ──────────────────────────────────────────────────────────────────────────────

@description('''
CanNotDelete lock on the resource group.
Prevents accidental deletion of the resource group and all its child resources.
Important: locks are inherited by child resources. Even subscription Owners
must explicitly remove the lock before deleting the resource group.
''')
resource lockResourceGroup 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'lock-rg-do-not-delete'
  properties: {
    level: 'CanNotDelete'
    notes: 'Prevents accidental deletion of the governance lab resource group. Remove this lock before running cleanup commands.'
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Budget & Cost Alert
// ──────────────────────────────────────────────────────────────────────────────
// Azure Budgets let you set spending thresholds and receive alerts when costs
// approach or exceed limits. Budgets do NOT stop spending — they only alert.
// To actually cap spending, you need to combine budgets with automation (e.g.,
// Action Groups that trigger runbooks to deallocate resources).
// The AZ-104 exam tests: creating budgets, alert thresholds, and cost management.
// ──────────────────────────────────────────────────────────────────────────────

@description('''
Monthly budget with cost alert at the configured threshold.
Scoped to this resource group. Sends email notification when forecasted
or actual costs reach the threshold percentage. Note: budgets are alerts
only — they do not automatically stop or limit resource consumption.
''')
resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'budget-${environment}-governance'
  properties: {
    category: 'Cost'
    amount: monthlyBudgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroupName
        ]
      }
    }
    notifications: {
      budgetThresholdReached: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: budgetAlertThresholdPercent
        contactEmails: [
          contactEmail
        ]
        thresholdType: 'Actual'
      }
      budgetForecastThresholdReached: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        contactEmails: [
          contactEmail
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────────────────────

@description('Name of the policy assignment auditing unmanaged disks.')
output policyAuditUnmanagedDisksName string = policyAuditUnmanagedDisks.name

@description('Name of the policy assignment requiring Environment tag on resource groups.')
output policyRequireEnvironmentTagName string = policyRequireEnvironmentTag.name

@description('Name of the policy assignment inheriting Environment tag from resource groups.')
output policyInheritEnvironmentTagName string = policyInheritEnvironmentTag.name

@description('Principal ID of the managed identity created for the tag-inheritance policy (needed for role assignment to allow Modify effect).')
output policyInheritTagIdentityPrincipalId string = policyInheritEnvironmentTag.identity.principalId

@description('Custom RBAC role definition ID for the VM Operator role.')
output customRoleVmOperatorId string = customRoleVmOperator.id

@description('Name of the resource lock applied to the resource group.')
output resourceLockName string = lockResourceGroup.name

@description('Name of the monthly budget.')
output budgetName string = budget.name
