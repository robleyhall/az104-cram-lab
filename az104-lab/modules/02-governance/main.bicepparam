using './main.bicep'

// ──────────────────────────────────────────────────────────────────────────────
// Module 02: Governance & Compliance — Parameter Overrides
// ──────────────────────────────────────────────────────────────────────────────
// Required: contactEmail must be set to receive budget alert notifications.
// Override other defaults below as needed for your environment.
// ──────────────────────────────────────────────────────────────────────────────

param contactEmail = 'admin@yourdomain.com'

// Uncomment to override defaults:
//   param location = 'westus2'
//   param environment = 'staging'
//   param monthlyBudgetAmount = 100
//   param budgetAlertThresholdPercent = 90
