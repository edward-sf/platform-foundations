// A user-assigned managed identity trusted by exactly one GitHub OIDC subject.

@description('Identity name, e.g. id-pf-dev.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object

@description('Federated credential name.')
param credentialName string

@description('Exact GitHub OIDC subject this identity trusts.')
param subject string

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: name
  location: location
  tags: tags
}

resource credential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: identity
  name: credentialName
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: subject
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
