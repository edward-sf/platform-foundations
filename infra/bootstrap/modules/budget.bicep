// Monthly cost budget with email alerts for the flagship threshold.
targetScope = 'subscription'

@description('Monthly budget in the billing currency.')
param amount int

@description('First day of the budget period, e.g. 2026-09-01T00:00:00Z.')
param startDate string

@description('Alert recipients.')
param contactEmails array

resource budget 'Microsoft.Consumption/budgets@2026-06-01' = {
  name: 'pf-budget'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      actual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
      }
    }
  }
}
