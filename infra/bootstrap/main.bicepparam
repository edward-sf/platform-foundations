using './main.bicep'

// Every value comes from the environment so nothing personal is committed.
// scripts/bootstrap.sh sets the PF_GITHUB_* and PF_BUDGET_START_DATE values.
param location = readEnvironmentVariable('PF_LOCATION')
param githubOwnerId = readEnvironmentVariable('PF_GITHUB_OWNER_ID')
param githubRepoId = readEnvironmentVariable('PF_GITHUB_REPO_ID')
param budgetEmail = readEnvironmentVariable('PF_BUDGET_EMAIL')
param budgetStartDate = readEnvironmentVariable('PF_BUDGET_START_DATE')
param deployBudget = bool(readEnvironmentVariable('PF_DEPLOY_BUDGET', 'true'))
