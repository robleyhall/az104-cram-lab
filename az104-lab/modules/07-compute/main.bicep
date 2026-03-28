// ================================================================
// Module 07: Compute — AZ-104 Certification Lab
// ================================================================
// Deploys VMs, VMSS, ACR, ACI, and App Service to cover the
// "Deploy and Manage Azure Compute Resources" domain (20–25% of exam).
// ================================================================

targetScope = 'resourceGroup'

// ──────────────────────────────────────────────────────────────────
// Parameters
// ──────────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Resource ID of the default subnet in spoke1 VNet (from Module 03). Used for Linux VM and VMSS NICs.')
param spoke1DefaultSubnetId string

@description('Resource ID of the app subnet in spoke1 VNet (from Module 03). Used for Windows VM NIC.')
param spoke1AppSubnetId string

@description('Admin username for both Linux and Windows VMs. AZ-104 tests knowledge of VM authentication options.')
@minLength(1)
@maxLength(64)
param adminUsername string = 'az104-labadmin'

@description('SSH public key for the Linux VM. Password auth is disabled — SSH keys are the recommended approach for Linux VMs.')
@secure()
param adminPublicKey string

@description('Password for the Windows VM admin account. Must meet Azure complexity requirements (12+ chars, uppercase, lowercase, number, special).')
@secure()
@minLength(12)
param adminPassword string

@description('Environment label applied to every resource via tags. Useful for policy-based governance exercises in Module 02.')
param environment string = 'az104-lab'

@description('Deterministic unique suffix derived from the resource group ID. Ensures globally unique names for ACR, App Service, etc.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Time zone for VM auto-shutdown schedules. Uses Windows time zone IDs.')
param shutdownTimeZone string = 'UTC'

// ──────────────────────────────────────────────────────────────────
// Variables
// ──────────────────────────────────────────────────────────────────

@description('Standard tags applied to every resource in this module for cost tracking and governance.')
var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'compute'
}

@description('Linux VM name following the naming convention: vm-{product}-{function}.')
var linuxVmName = 'vm-az104-lab-linux1'

@description('Windows VM name following the naming convention.')
var windowsVmName = 'vm-az104-lab-win1'

@description('VMSS name following the naming convention.')
var vmssName = 'vmss-az104-lab-web'

@description('Availability set for Windows VMs. AZ-104 tests the difference between availability sets and availability zones.')
var availabilitySetName = 'avset-az104-lab-win'

@description('ACR name — must be globally unique, alphanumeric only, 5-50 chars.')
var acrName = 'acraz104-lab${uniqueSuffix}'

@description('Container Instance name.')
var aciName = 'ci-az104-lab-hello'

@description('App Service Plan name.')
var appServicePlanName = 'plan-az104-lab-web'

@description('App Service name — must be globally unique as it becomes a DNS name.')
var appServiceName = 'app-az104-lab-web-${uniqueSuffix}'

@description('Nginx install script encoded as base64 for the custom script extension. AZ-104 frequently tests custom script extensions.')
var nginxInstallScript = base64('#!/bin/bash\napt-get update && apt-get install -y nginx')

// ──────────────────────────────────────────────────────────────────
// Networking: NICs and Public IPs
// ──────────────────────────────────────────────────────────────────

@description('Public IP for the Linux VM. AZ-104 tests public IP SKUs (Basic vs Standard) and allocation methods.')
resource linuxPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-${linuxVmName}'
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  zones: ['1']
}

@description('NIC for the Linux VM connected to spoke1/default subnet.')
resource linuxNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${linuxVmName}'
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: spoke1DefaultSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: linuxPublicIp.id
          }
        }
      }
    ]
  }
}

@description('NIC for the Windows VM connected to spoke1/app subnet.')
resource windowsNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${windowsVmName}'
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: spoke1AppSubnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────
// Availability Set
// ──────────────────────────────────────────────────────────────────

@description('''
Availability set for the Windows VM. Key AZ-104 concepts:
  - Fault domains (FD): Physical rack isolation — protects against hardware failures.
  - Update domains (UD): Logical grouping — only one UD reboots at a time during maintenance.
  - Cannot mix availability sets and availability zones for the same VM.
  - Max 3 FDs and 20 UDs per set.
''')
resource availabilitySet 'Microsoft.Compute/availabilitySets@2024-07-01' = {
  name: availabilitySetName
  location: location
  tags: commonTags
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
}

// ──────────────────────────────────────────────────────────────────
// Linux VM
// ──────────────────────────────────────────────────────────────────

@description('''
Linux VM running Ubuntu 22.04 LTS. Key AZ-104 concepts covered:
  - SSH key authentication (no password) — recommended for Linux.
  - Availability zone placement — zone 1.
  - Standard_B1s — burstable B-series, cheapest VM size.
  - Managed disk with Standard_LRS — cheapest disk tier.
  - Boot diagnostics with managed storage account.
  - Custom script extension to install nginx post-deployment.
''')
resource linuxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: linuxVmName
  location: location
  tags: commonTags
  zones: ['1']
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: linuxVmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${linuxVmName}'
        createOption: 'FromImage'
        diskSizeGB: 30
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: linuxNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

@description('Custom script extension to install nginx on the Linux VM. AZ-104 frequently tests VM extensions — know the difference between Custom Script, DSC, and diagnostic extensions.')
resource linuxVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: linuxVm
  name: 'install-nginx'
  location: location
  tags: commonTags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: nginxInstallScript
    }
  }
}

@description('Auto-shutdown schedule for the Linux VM to save costs. Runs at 10 PM every day.')
resource linuxVmShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${linuxVmName}'
  location: location
  tags: commonTags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '2200'
    }
    timeZoneId: shutdownTimeZone
    targetResourceId: linuxVm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// Windows VM
// ──────────────────────────────────────────────────────────────────

@description('''
Windows Server 2022 VM. Key AZ-104 concepts covered:
  - Password authentication — typical for Windows VMs.
  - Standard_B2s — slightly larger burstable VM (2 vCPUs, 4 GiB RAM).
  - Availability set placement — cannot use zones when using an availability set.
  - Boot diagnostics with managed storage.
''')
resource windowsVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: windowsVmName
  location: location
  tags: commonTags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    availabilitySet: {
      id: availabilitySet.id
    }
    osProfile: {
      computerName: windowsVmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
        enableAutomaticUpdates: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${windowsVmName}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: windowsNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

@description('Auto-shutdown schedule for the Windows VM. Same 10 PM schedule as the Linux VM.')
resource windowsVmShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${windowsVmName}'
  location: location
  tags: commonTags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '2200'
    }
    timeZoneId: shutdownTimeZone
    targetResourceId: windowsVm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// Virtual Machine Scale Set (VMSS)
// ──────────────────────────────────────────────────────────────────

@description('''
VMSS running Ubuntu 22.04 with nginx. Key AZ-104 concepts:
  - Uniform orchestration mode for identical instances.
  - Rolling upgrade policy — controls blast radius during updates.
  - Autoscale rules based on CPU — scale-out and scale-in thresholds.
  - Custom script extension applied to every instance.
  - Instances are spread across availability zones automatically.
''')
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-07-01' = {
  name: vmssName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_B1s'
    tier: 'Standard'
    capacity: 2
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Rolling'
      rollingUpgradePolicy: {
        maxBatchInstancePercent: 20
        maxUnhealthyInstancePercent: 20
        maxUnhealthyUpgradedInstancePercent: 20
        pauseTimeBetweenBatches: 'PT5S'
      }
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'vmss-web'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminPublicKey
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-${vmssName}'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: spoke1DefaultSubnetId
                    }
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'install-nginx'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                script: nginxInstallScript
              }
            }
          }
        ]
      }
    }
  }
}

@description('''
Autoscale settings for the VMSS. Key AZ-104 concepts:
  - Scale-out rule: CPU > 70% for 5 minutes → add 1 instance.
  - Scale-in rule: CPU < 30% for 5 minutes → remove 1 instance.
  - Cooldown period (PT5M): prevents rapid scaling oscillation.
  - Min/max instance counts define scaling boundaries.
  - AZ-104 tests understanding of metric-based vs schedule-based autoscale.
''')
resource vmssAutoscale 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: 'autoscale-${vmssName}'
  location: location
  tags: commonTags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'default'
        capacity: {
          minimum: '1'
          maximum: '5'
          default: '2'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────
// Azure Container Registry (ACR)
// ──────────────────────────────────────────────────────────────────

@description('''
Azure Container Registry for storing container images. Key AZ-104 concepts:
  - Basic SKU — cheapest tier, suitable for dev/test.
  - Admin user enabled for lab simplicity.
    ⚠ Best practice: Use managed identity or service principal for production.
  - SKU tiers: Basic → Standard → Premium (geo-replication, private endpoints).
  - ACR name must be globally unique and alphanumeric only.
''')
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: commonTags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ──────────────────────────────────────────────────────────────────
// Azure Container Instance (ACI)
// ──────────────────────────────────────────────────────────────────

@description('''
Azure Container Instance running a hello-world container. Key AZ-104 concepts:
  - Serverless containers — no VM management needed.
  - Best for simple, short-lived, or burst workloads.
  - Supports Linux and Windows containers.
  - Can mount Azure Files shares as volumes.
  - Restart policies: Always, OnFailure, Never.
  - Not suitable for long-running production workloads (use AKS or Container Apps).
''')
resource aci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: aciName
  location: location
  tags: commonTags
  properties: {
    containers: [
      {
        name: 'aci-helloworld'
        properties: {
          image: 'mcr.microsoft.com/azuredocs/aci-helloworld:latest'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: json('0.5')
              memoryInGB: json('0.5')
            }
          }
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'OnFailure'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// App Service Plan + App Service + Deployment Slot
// ──────────────────────────────────────────────────────────────────

@description('''
App Service Plan (Linux, B1 SKU). Key AZ-104 concepts:
  - B1 is the cheapest SKU that supports deployment slots.
  - Free/Shared tiers do NOT support slots, custom domains with SSL, or Always On.
  - Plan SKU determines available features: scaling, slots, VNet integration.
  - Linux plans must set reserved=true (legacy API requirement).
  - AZ-104 tests knowledge of which features are available at which pricing tiers.
''')
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

@description('''
App Service (Web App) running Node 18 LTS on Linux. Key AZ-104 concepts:
  - HTTPS Only redirects all HTTP traffic to HTTPS.
  - Always On keeps the app warm — disabled here to save cost (B1 supports it).
  - linuxFxVersion sets the runtime stack (e.g., NODE|18-lts, PYTHON|3.11, DOTNETCORE|8.0).
  - App Settings are environment variables — used for configuration without code changes.
  - AZ-104 tests deployment methods: slots, ZIP deploy, GitHub Actions, local Git.
''')
resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  tags: commonTags
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

@description('''
Staging deployment slot for the App Service. Key AZ-104 concepts:
  - Slots allow zero-downtime deployments via swap operations.
  - Each slot is a live app with its own hostname.
  - Slot settings (connection strings, app settings) can be "sticky" to a slot.
  - Swap operations exchange routing rules, not files — instant and atomic.
  - B1+ SKU is required for deployment slots.
  - AZ-104 frequently tests slot swap behavior and sticky settings.
''')
resource stagingSlot 'Microsoft.Web/sites/slots@2024-04-01' = {
  parent: appService
  name: 'staging'
  location: location
  tags: commonTags
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// ──────────────────────────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────────────────────────

@description('Resource ID of the Linux VM. Used by Module 08 (Monitoring) for diagnostic settings.')
output linuxVmId string = linuxVm.id

@description('Resource ID of the Windows VM.')
output windowsVmId string = windowsVm.id

@description('Resource ID of the VMSS.')
output vmssId string = vmss.id

@description('ACR login server URL (e.g., acraz104-labxyz.azurecr.io). Used to push/pull container images.')
output acrLoginServer string = acr.properties.loginServer

@description('Public IP address of the ACI container instance.')
output aciIpAddress string = aci.properties.ipAddress.ip

@description('Default hostname of the App Service (e.g., app-az104-lab-web-xyz.azurewebsites.net).')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('Name of the ACR for use in downstream commands.')
output acrName string = acr.name

@description('Default hostname of the staging slot.')
output stagingSlotUrl string = 'https://${stagingSlot.properties.defaultHostName}'
