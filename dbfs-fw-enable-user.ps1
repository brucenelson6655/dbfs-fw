Update-AzDatabricksWorkspace `
   -Name "<workspace-name>" `
   -ResourceGroupName "<resource-group-name>" `
   -SubscriptionId "<subscription-ID>" `
   -Sku "Premium" `
   -AccessConnectorId "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.Databricks/accessConnectors/<access-connector-name>" `
   -AccessConnectorIdentityType "UserAssigned" `
   -AccessConnectorUserAssignedIdentityId "/subscriptions/<subscription-id>/resourceGroups/<resource-group-name>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<managed-identity-name>" `
   -DefaultStorageFirewall "Enabled"
