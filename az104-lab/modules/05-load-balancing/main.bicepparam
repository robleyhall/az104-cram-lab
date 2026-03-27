using './main.bicep'

// Use defaults for all parameters.
// Override here when deploying to a different region or environment:
//   param location = 'westus2'
//   param environment = 'staging'

// Supply the spoke subnet ID from Module 03 output for backend pool references:
//   param spoke1SubnetId = '/subscriptions/{sub}/resourceGroups/rg-certlab-networking/providers/Microsoft.Network/virtualNetworks/vnet-certlab-spoke1/subnets/default'
