using './main.bicep'

// ──────────────────────────────────────────────────────────────────
// Module 07: Compute — Parameter Values
// ──────────────────────────────────────────────────────────────────
// Required parameters that have no defaults must be supplied here
// or via --parameters on the CLI.
//
// ⚠ NEVER commit real secrets to source control.
//   Use Azure Key Vault references, environment variables, or
//   pass secrets at deployment time with --parameters.
// ──────────────────────────────────────────────────────────────────

// Subnet IDs from Module 03 (Networking) — replace with actual resource IDs
param spoke1DefaultSubnetId = '<REPLACE: /subscriptions/{sub}/resourceGroups/rg-certlab-networking/providers/Microsoft.Network/virtualNetworks/vnet-certlab-spoke1/subnets/default>'
param spoke1AppSubnetId = '<REPLACE: /subscriptions/{sub}/resourceGroups/rg-certlab-networking/providers/Microsoft.Network/virtualNetworks/vnet-certlab-spoke1/subnets/app>'

// SSH public key for the Linux VM — paste your public key here
// Generate one with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/az104-certlab
param adminPublicKey = '<REPLACE: paste contents of ~/.ssh/az104-certlab.pub>'

// Windows VM password — supply at deploy time instead of hardcoding:
//   az deployment group create ... --parameters adminPassword='YourP@ssw0rd!'
param adminPassword = '<REPLACE: supply-at-deploy-time>'

// Override defaults if needed:
//   param location = 'westus2'
//   param adminUsername = 'yourname'
//   param environment = 'staging'
//   param shutdownTimeZone = 'Eastern Standard Time'
