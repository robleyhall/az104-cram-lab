using './main.bicep'

// Required parameters — replace with outputs from Modules 00 and 03.
// Run these commands to get the values:
//
//   az deployment group show -g rg-az104-lab-foundation -n main \
//     --query properties.outputs.hubVnetId.value -o tsv
//
//   az deployment group show -g rg-az104-lab-networking -n main \
//     --query properties.outputs.spoke1VnetId.value -o tsv
//
//   az deployment group show -g rg-az104-lab-networking -n main \
//     --query properties.outputs.spoke1DataSubnetId.value -o tsv

param hubVNetId = '<hub-vnet-resource-id>'
param spoke1VNetId = '<spoke1-vnet-resource-id>'
param spoke1DataSubnetId = '<spoke1-data-subnet-resource-id>'

// Optional overrides — uncomment and adjust as needed:
//   param location = 'westus2'
//   param environment = 'staging'
//   param deployBastion = false
//   param deployPrivateEndpoint = true
//   param storageAccountResourceId = '<storage-account-resource-id>'
