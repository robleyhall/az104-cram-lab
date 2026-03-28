// ================================================================
// Module 01: Identity & Entra ID — Azure Resource Deployment
// AZ-104 CertForge Lab
// ================================================================
// Entra ID (users, groups, SSPR) is a tenant-level service managed
// via Azure CLI / Portal, not ARM/Bicep. This file deploys the
// Azure-resource-level identity primitives that pair with the
// Entra ID objects created by entra-setup.sh.
// ================================================================

targetScope = 'resourceGroup'

// ──────────────────────────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────────────────────────

@description('Azure region for deployed resources.')
param location string = 'eastus'

@description('Environment label used in naming and tagging.')
@allowed(['az104-lab', 'dev', 'test'])
param environment string = 'az104-lab'

@description('Project-wide prefix applied to resource names.')
param projectPrefix string = 'az104'

@description('Principal ID of the Entra ID group that should receive Contributor on this resource group. Leave empty to skip.')
param contributorGroupPrincipalId string = ''

@description('Principal ID of the Entra ID group that should receive Reader on this resource group. Leave empty to skip.')
param readerGroupPrincipalId string = ''

// ──────────────────────────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────────────────────────

var tags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'identity'
}

var managedIdentityName = '${projectPrefix}-${environment}-identity-uami'

// Built-in role definition IDs (well-known GUIDs)
var contributorRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b24988ac-6180-42a0-ab88-20f7382dd24c'
)
var readerRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
)

// ──────────────────────────────────────────────────────────────────
// Resources
// ──────────────────────────────────────────────────────────────────

@description('User Assigned Managed Identity — demonstrates Azure identity concepts and can be referenced by other modules.')
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

@description('Assigns Contributor role to the az104-lab-admins Entra ID group on this resource group.')
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =
  if (!empty(contributorGroupPrincipalId)) {
    name: guid(resourceGroup().id, contributorGroupPrincipalId, contributorRoleDefinitionId)
    properties: {
      roleDefinitionId: contributorRoleDefinitionId
      principalId: contributorGroupPrincipalId
      principalType: 'Group'
      description: 'AZ-104 Lab — Contributor for az104-lab-admins group'
    }
  }

@description('Assigns Reader role to the az104-lab-readers Entra ID group on this resource group.')
resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' =
  if (!empty(readerGroupPrincipalId)) {
    name: guid(resourceGroup().id, readerGroupPrincipalId, readerRoleDefinitionId)
    properties: {
      roleDefinitionId: readerRoleDefinitionId
      principalId: readerGroupPrincipalId
      principalType: 'Group'
      description: 'AZ-104 Lab — Reader for az104-lab-readers group'
    }
  }

@description('Assigns Reader role to the managed identity itself (demonstrates identity-to-role binding).')
resource uamiReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, readerRoleDefinitionId)
  properties: {
    roleDefinitionId: readerRoleDefinitionId
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'AZ-104 Lab — Reader for managed identity (demonstrates identity role binding)'
  }
}

// ──────────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────────

@description('Resource ID of the User Assigned Managed Identity.')
output managedIdentityId string = managedIdentity.id

@description('Principal (object) ID of the managed identity — use for downstream role assignments.')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Client ID of the managed identity.')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Name of the managed identity resource.')
output managedIdentityName string = managedIdentity.name
