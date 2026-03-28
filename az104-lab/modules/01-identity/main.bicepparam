using './main.bicep'

// ================================================================
// Module 01: Identity & Entra ID — Parameter File
// ================================================================
// Adjust these values to match your environment.
// After running entra-setup.sh, paste the group principal IDs
// here to wire up RBAC role assignments via Bicep.
// ================================================================

param location = 'eastus'
param environment = 'az104-lab'
param projectPrefix = 'az104'

// Populate these after running entra-setup.sh — it prints the object IDs.
// Example: param contributorGroupPrincipalId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
param contributorGroupPrincipalId = ''
param readerGroupPrincipalId = ''
