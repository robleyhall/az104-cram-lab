// ──────────────────────────────────────────────────────────────────────────────
// Module 03 — Virtual Networking — Parameters
// ──────────────────────────────────────────────────────────────────────────────
// Before deploying, replace the hubVNetResourceId placeholder with the actual
// resource ID from Module 00. Retrieve it with:
//
//   az network vnet show \
//     --resource-group rg-certlab-foundation \
//     --name vnet-certlab-hub \
//     --query id -o tsv
// ──────────────────────────────────────────────────────────────────────────────

using './main.bicep'

param location = 'eastus'

param hubVNetResourceId = '<run: az network vnet show -g rg-certlab-foundation -n vnet-certlab-hub --query id -o tsv>'

// Replace '*' with your public IP for secure SSH access (e.g., '203.0.113.42')
param allowedSourceIP = '*'

param environment = 'certlab'
