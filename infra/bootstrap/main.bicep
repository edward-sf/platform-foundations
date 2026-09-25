// Secret-free bootstrap: Terraform state storage, one workload identity per
// environment, a narrow custom role, and a budget. Run once by the operator.
targetScope = 'subscription'

@description('Azure region for all resources.')
param location string

@description('Numeric GitHub owner ID (gh api repos/edward-sf/platform-foundations --jq .owner.id).')
param githubOwnerId string

@description('Numeric GitHub repository ID (gh api repos/edward-sf/platform-foundations --jq .id).')
param githubRepoId string

@description('Budget alert email. Supplied at deploy time; never committed.')
param budgetEmail string

@description('Deploy the budget (false if the subscription offer rejects budgets).')
param deployBudget bool = true

@description('Budget start date; reused from an existing budget on redeploy.')
param budgetStartDate string

@description('Monthly budget amount.')
param budgetAmount int = 2

var tags = {
  project: 'platform-foundations'
  'managed-by': 'bicep'
  env: 'shared'
}
var environments = [
  'dev'
  'prod'
]

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: 'rg-pf-bootstrap'
  location: location
  tags: tags
}

module storage 'modules/storage.bicep' = {
  scope: rg
  name: 'pf-storage'
  params: {
    name: 'stpf${uniqueString(subscription().id)}'
    location: location
    tags: tags
    containerNames: [for env in environments: 'tfstate-${env}']
  }
}

module role 'modules/role.bicep' = {
  scope: rg
  name: 'pf-role'
}

module identities 'modules/identity.bicep' = [
  for env in environments: {
    scope: rg
    name: 'pf-identity-${env}'
    params: {
      name: 'id-pf-${env}'
      location: location
      tags: tags
      credentialName: 'github-${env}'
      subject: 'repository_owner_id:${githubOwnerId}:repository_id:${githubRepoId}:environment:${env}'
    }
  }
]

module stateAccess 'modules/state-access.bicep' = [
  for (env, i) in environments: {
    scope: rg
    name: 'pf-state-access-${env}'
    params: {
      storageAccountName: storage.outputs.name
      containerName: 'tfstate-${env}'
      principalId: identities[i].outputs.principalId
      roleDefinitionId: role.outputs.roleDefinitionId
    }
  }
]

module budget 'modules/budget.bicep' = if (deployBudget) {
  name: 'pf-budget'
  params: {
    amount: budgetAmount
    startDate: budgetStartDate
    contactEmails: [
      budgetEmail
    ]
  }
}

output tenantId string = tenant().tenantId
output subscriptionId string = subscription().subscriptionId
output storageAccountName string = storage.outputs.name
output devClientId string = identities[0].outputs.clientId
output prodClientId string = identities[1].outputs.clientId
output roleDefinitionId string = role.outputs.roleDefinitionId
