Import-Module -Name '.\AzureADScanner'

$Computers = Get-Content -Path 'computers.json' | ConvertFrom-Json
$Computers | Invoke-AzureADSync -Token ""
