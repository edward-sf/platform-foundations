// Terraform state storage: Entra-only access, versioned, soft-deleted, delete-locked.

@description('Globally unique storage account name.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Blob containers to create, one per environment.')
param containerNames array

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: account
  name: 'default'
  properties: {
    isVersioningEnabled: true
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = [
  for containerName in containerNames: {
    parent: blobService
    name: containerName
    properties: {
      publicAccess: 'None'
    }
  }
]

resource deleteLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: 'pf-state-lock'
  scope: account
  properties: {
    level: 'CanNotDelete'
    notes: 'Protects Terraform state. Remove only through scripts/teardown.sh.'
  }
}

output name string = account.name
