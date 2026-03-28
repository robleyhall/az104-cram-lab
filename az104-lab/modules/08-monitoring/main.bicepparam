using './main.bicep'

// Required: email address for alert notifications
param contactEmail = 'admin@az104-lab.example.com'

// Optional: supply a VM resource ID from Module 07 to enable the CPU metric alert.
// Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{name}
// Uncomment and replace with your VM's resource ID after deploying Module 07:
//   param vmResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-az104-lab-compute/providers/Microsoft.Compute/virtualMachines/vm-az104-lab-linux'

// Use defaults for location and environment.
// Override here when deploying to a different region or environment:
//   param location = 'westus2'
//   param environment = 'staging'
