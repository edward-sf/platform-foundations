// Custom role: read and write Terraform state blobs, nothing more.

@description('Role name shown in the portal; teardown deletes it by this name.')
param roleName string = 'Terraform State Writer (pf)'

resource role 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(subscription().id, 'pf-terraform-state-writer')
  properties: {
    roleName: roleName
    description: 'Read and write Terraform state blobs. No blob delete, no container management, no user-delegation keys.'
    type: 'customRole'
    permissions: [
      {
        actions: []
        notActions: []
        dataActions: [
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

output roleDefinitionId string = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.name)
