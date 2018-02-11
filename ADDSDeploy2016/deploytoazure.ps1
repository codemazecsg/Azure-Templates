
param (
    [Parameter (Mandatory=$true)] [string] $subscriptionName,
    [Parameter (Mandatory=$true)] [string] $resourceGroupLocation,
    [Parameter (Mandatory=$true)] [string] $resourceGroupName,
    [Parameter (Mandatory=$true)] [string] $templateFile,
    [Parameter (Mandatory=$true)] [string] $parameterFile
)

# note: you must be logged in (Login-AzureRmAccount) before calling this script

# load PS module
Import-Module Azure -ErrorAction Stop

# select subscription
Select-AzureRmSubscription -SubscriptionName $subscriptionName

# create or update the resource group
New-AzureRmResourceGroup -Name $resourceGroupName -Location $resourceGroupLocation -Verbose -Force -ErrorAction Stop

# perform deployment
New-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName `
                                   -TemplateFile $templateFile `
                                   -TemplateParameterFile $parameterFile `
                                   -Verbose -Force -ErrorAction Stop

