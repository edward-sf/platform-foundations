// Grants one identity the state role on one container, and nowhere else.

@description('Storage account holding the container.')
param storageAccountName string

@description('Container to grant access to.')
param containerName string

@description('Principal ID of the identity.')
param principalId string

@description('Subscription-level resource ID of the role definition.')
param roleDefinitionId string

resource account 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' existing = {
  parent: account
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' existing = {
  parent: blobService
  name: containerName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(container.id, principalId, roleDefinitionId)
  scope: container
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
