using './main.bicep'

// Use defaults for location, environment, and uniqueSuffix.
// Override here when deploying to a different region or environment:
//   param location = 'westus2'
//   param environment = 'staging'

// Required — supply the spoke1/data subnet resource ID from the networking module:
param dataSubnetId = '<replace-with-spoke1-data-subnet-resource-id>'
