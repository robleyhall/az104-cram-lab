// ============================================================================
// Module 06: Storage
// AZ-104 Certification Lab — Storage accounts, blob containers, file shares,
// lifecycle management, SAS tokens, encryption, and replication
// Exam weight: 15–20 %
// ============================================================================

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment label used in naming and tags.')
param environment string = 'certlab'

@description('Deterministic unique suffix for globally unique names. Derived from the resource group ID by default.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Resource ID of the spoke1/data subnet. Used in storage firewall virtual‑network rules.')
param dataSubnetId string

// ── Variables ───────────────────────────────────────────────────────────────

var commonTags = {
  Environment: environment
  Project: 'az104-lab'
  Module: 'storage'
  CostCenter: 'training'
}

// Storage account names must be 3‑24 chars, lowercase alphanumeric only.
// The prefix + uniqueSuffix (13 chars) stays well within limits.
var primaryStorageName = 'stcertlabpri${uniqueSuffix}'
var replicaStorageName = 'stcertlabrep${uniqueSuffix}'

// ── Primary Storage Account ─────────────────────────────────────────────────
// Redundancy note: This lab uses Standard_LRS for cost savings.
// Production workloads should consider:
//   - Standard_ZRS  — zone‑redundant (3 copies across availability zones)
//   - Standard_GRS  — geo‑redundant (6 copies, 2 regions, read after failover)
//   - Standard_RAGRS — read‑access geo‑redundant (read replica anytime)
//   - Standard_GZRS — geo‑zone‑redundant (best durability)
//   - Standard_RAGZRS — read‑access geo‑zone‑redundant

@description('Primary storage account for blob containers, file shares, and lifecycle management demos.')
resource primaryStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: primaryStorageName
  location: location
  tags: commonTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    // Shared key access is enabled for lab exercises (SAS token generation, etc.).
    // Security best practice for production: set to false and use Entra ID RBAC.
    allowSharedKeyAccess: true
    allowBlobPublicAccess: true // Required for the certlab-public container demo
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: dataSubnetId
          action: 'Allow'
        }
      ]
      ipRules: []
    }
    encryption: {
      services: {
        blob: { enabled: true, keyType: 'Account' }
        file: { enabled: true, keyType: 'Account' }
        table: { enabled: true, keyType: 'Account' }
        queue: { enabled: true, keyType: 'Account' }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ── Blob Services (soft delete, versioning) ─────────────────────────────────

@description('Blob service configuration: soft delete (7 days), versioning enabled.')
resource primaryBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: primaryStorage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
  }
}

// ── File Services (soft delete) ─────────────────────────────────────────────

@description('File service configuration: soft delete (7 days).')
resource primaryFileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: primaryStorage
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// ── Blob Containers ─────────────────────────────────────────────────────────

@description('Private blob container for lab data and lifecycle management demos.')
resource dataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: primaryBlobService
  name: 'certlab-data'
  properties: {
    publicAccess: 'None'
  }
}

@description('Blob‑level public access container for demonstrating anonymous read access.')
resource publicContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: primaryBlobService
  name: 'certlab-public'
  properties: {
    publicAccess: 'Blob'
  }
}

// ── File Share ───────────────────────────────────────────────────────────────

@description('Azure Files share for SMB/NFS file share exercises (5 GB quota, Hot tier).')
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: primaryFileService
  name: 'certlab-files'
  properties: {
    shareQuota: 5
    accessTier: 'Hot'
  }
}

// ── Lifecycle Management Policy ─────────────────────────────────────────────

@description('Blob lifecycle management: Cool at 30 d → Archive at 90 d → Delete at 365 d. Applied to blockBlobs in certlab-data.')
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: primaryStorage
  name: 'default'
  dependsOn: [primaryBlobService]
  properties: {
    policy: {
      rules: [
        {
          name: 'moveToCoolAfter30Days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['certlab-data/']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
              }
            }
          }
        }
        {
          name: 'moveToArchiveAfter90Days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['certlab-data/']
            }
            actions: {
              baseBlob: {
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
              }
            }
          }
        }
        {
          name: 'deleteAfter365Days'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['certlab-data/']
            }
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
            }
          }
        }
      ]
    }
  }
}

// ── Replica Storage Account ─────────────────────────────────────────────────
// Object replication requires:
//   1. Blob versioning enabled on both source and destination
//   2. Change feed enabled on the source account
//   3. A replication policy linking source → destination containers
// Replication policies cannot be fully configured in Bicep today.
// After deploying this template, configure object replication via CLI or Portal:
//
//   az storage account or-policy create \
//     --account-name <primaryStorageName> \
//     --destination-account <replicaStorageName> \
//     --source-container certlab-data \
//     --destination-container certlab-data-replica \
//     --min-creation-time '<ISO‑8601>'
//
// See: https://learn.microsoft.com/azure/storage/blobs/object-replication-configure

@description('Replica storage account used as the destination for object replication exercises.')
resource replicaStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: replicaStorageName
  location: location
  tags: commonTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
  }
}

@description('Blob service on the replica account with versioning enabled (required for object replication).')
resource replicaBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: replicaStorage
  name: 'default'
  properties: {
    isVersioningEnabled: true
  }
}

@description('Destination container for object replication from certlab-data.')
resource replicaContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: replicaBlobService
  name: 'certlab-data-replica'
  properties: {
    publicAccess: 'None'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('Resource ID of the primary storage account.')
output primaryStorageAccountId string = primaryStorage.id

@description('Name of the primary storage account.')
output primaryStorageAccountName string = primaryStorage.name

@description('Name of the replica storage account.')
output replicaStorageAccountName string = replicaStorage.name

@description('Primary blob service endpoint URL.')
output primaryBlobEndpoint string = primaryStorage.properties.primaryEndpoints.blob
