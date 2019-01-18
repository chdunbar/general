<#
    ----- NOTE -----
    1.  If 'solutionsStorageAccountConnectionString' is empty or null, the script will attempt solution deployments living in the PROD SDS instance
    2.  If 'solutionsStorageAccountConnectionString' is NOT null or empty, the script will attempt solution deployments living in the specified SANDBOX SDS instance (i.e. Custom Solutions)
    3.  'solutionType' refers to the solution type id like 'remote-monitoring', THIS SHOULD BE LOWERCASE, even if the pushed solution had uppercase chars
    4.  If 'solutionVariant' is not applicable, or you want to deploy the default, leave blank. Otherwise, it expects the variant diff from the Manifest file name:
            i.e. If you have two variants, ('Manifest.xml' and 'ManifestJava.xml'), set 'solutionVariant' to '' for default and 'Java' for the variant. CASE SENSITIVE
    5.  'solutionName' refers to the name of the resource group that will be created
    6.  'deploymentSubscriptionId' refers to the Azure subscription the solution will deploy to
    7.  'deploymentTenantId' MUST BE the tenantId where 'deploymentSubscriptionId' lives, this affects the authorization tokens that the script gets
    8.  'location' is the Azure region to deploy to (i.e. 'East US' **Note: It is not of the form 'eastus')
    9.  If 'numberOfDeployments' is greater than 1, the script will simply START the deployments (as currently written, it does not accomodate solutions with manual steps)
    10. If 'numberOfDeployments' == 1, the script will deploy/monitor a single deployment, printing updates as well as a total deployment time at the end
    11. If the deployment has a manual input step, you can point to a json file that contains the preferred inputs, relative to where the script runs (NOTE: currently written to only support a single manual step)
            {
                "inputVarName": "preferredInputValue",
                "inputVarName2": "preferredInputValue2"
            }
#>

# This param list is for specifying the values AND THEN running the script
param (
    [string]$solutionsStorageAccountConnectionString = "arbConnectionString",
    [string]$solutionType = "arb-solutionType",
    [string]$solutionVariant = "",
    [string]$solutionName = "arb-solutionName",
    [string]$deploymentSubscriptionId = "arbGuid",
    [string]$deploymentTenantId = "arbGuid",
    [string]$location = "East US",
    [int]$numberOfDeployments = "1",
    [string]$manualInputParametersFile = "./arbInputs.json"
)

<#
# This param list is for providing all values AFTER the script is invoked
param (
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$solutionsStorageAccountConnectionString = "",
    [Parameter(Mandatory = $true)]
    [string]$solutionType = "",
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$solutionVariant = "",
    [Parameter(Mandatory = $true)]
    [string]$solutionName = "",
    [Parameter(Mandatory = $true)]
    [string]$deploymentSubscriptionId = "",
    [Parameter(Mandatory = $true)]
    [string]$deploymentTenantId = "",
    [Parameter(Mandatory = $true)]
    [string]$location = "",
    [Parameter(Mandatory = $true)]
    [int]$numberOfDeployments = "",
    [Parameter(Mandatory = $true)]
    [string]$manualInputParametersFile = ""
)
#>

$deploymentEndpoint = "https://sds-api.azureiotsolutions.com/"

$ErrorActionPreference = 'Stop'

function GetAuthToken
{
       param
       (
              [Parameter(Mandatory=$true)]
              $TenantName,
              [Parameter(Mandatory=$true)]
              $resourceAppIdURI
       )

       $adal = "${env:ProgramFiles(x86)}\WindowsPowerShell\Modules\Azure\5.1.2\Services\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
       $adalforms = "${env:ProgramFiles(x86)}\WindowsPowerShell\Modules\Azure\5.1.2\Services\Microsoft.IdentityModel.Clients.ActiveDirectory.WindowsForms.dll"

       [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
       [System.Reflection.Assembly]::LoadFrom($adalforms) | Out-Null

       $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"
       $redirectUri = "urn:ietf:wg:oauth:2.0:oob"

       #$resourceAppIdURI = "https://graph.windows.net/"
       #$resourceAppIdURI = "https://management.core.windows.net/"
       #$resourceAppIdURI = "https://management.core.usgovcloudapi.net"
       #$resourceAppIdURI = "https://management.azure.com/"

       $authority = "https://login.windows.net/$TenantName"
       $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority

       $authResult = $authContext.AcquireToken($resourceAppIdURI, $clientId,$redirectUri, "Auto")

       return $authResult
}

function MonitorAndPrintDeployment {
    param
    (
        [Parameter(Mandatory = $true)]
        $Subscription,
         
        [Parameter(Mandatory = $true)]
        $UniqueId 
    )

    do
    {
        Start-Sleep -m 1000
        $deploymentDetails = Invoke-RestMethod "${deploymentEndpoint}api/deployments/${Subscription}/${UniqueId}" -Headers $header -Method GET -ContentType "application/json"
        $deployment = $deploymentDetails.deployment
        $provisioningSteps = $deploymentDetails.provisioningSteps
        $status = $deployment.status

        if ($provisioningSteps -ne $null) {
            $currentProvisioningStep = $provisioningSteps[$deployment.currentProvisioningStep]                
            $message = $currentProvisioningStep.Title
            if ($status -notlike 'ready') {
                $message = "$message..."
            } else {
                $message = "$message!"
            }
        } else {
            $message = "Deployment is being created..."
        }

        if ($oldMessage -ne $message) {
            $TimeStamp = (Get-Date)
            Write-Host "$TimeStamp"
            Write-Host $message
        }

        $oldMessage = $message
    }
    while ($status -notlike 'failed' -and $status -notlike 'actionRequired' -and $status -notlike 'ready')

    return $deploymentDetails
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} ;
$token = GetAuthToken $deploymentTenantId "https://management.core.windows.net/"
$managementToken = $token.AccessToken
$token = GetAuthToken $deploymentTenantId "https://graph.windows.net/"
$graphToken = $token.AccessToken

$header = @{
    'Content-Type'  = 'application\json'
    'Authorization' = "Bearer $managementToken"
    'MS-GraphToken' = "$graphToken"
}

$payload = @{
    Location = $location
    Name = $solutionName
    Subscription = $deploymentSubscriptionId
    TemplateId = $solutionType
}

$solutionTemplate = $solutionType

if ($solutionsStorageAccountConnectionString.length -gt 0) {
    $solutionTemplate = "$solutionType" + '@user'
    $payload.TemplateId = $solutionTemplate

    $payload.SolutionStorageConnectionString = $solutionsStorageAccountConnectionString
}

if ($solutionVariant.length -gt 0) {
    $payload.TemplateVariant = $solutionVariant
}

if ($numberOfDeployments -gt 1) {

    $intInc = 0

    do {

        $payload.Name = $solutionName + $intInc

        Write-Host "Creating new SDS deployment of ${solutionType} into $($solutionName + $intInc)..."

        $body = $payload | ConvertTo-Json 
        $deployment = Invoke-RestMethod "${deploymentEndpoint}api/deployments/${deploymentSubscriptionId}/${solutionTemplate}" -Headers $header -Method POST -Body $body -ContentType "application/json"

        Write-Host "New deployment:"
        $deployment

        $uniqueId = $deployment.uniqueId

        $intInc = $intInc + 1
    }
    while ($intInc -lt $numberOfDeployments)

} else {

    Write-Host "Creating new SDS deployment of ${solutionType} into ${solutionName}..."

    $StartDateTime = (Get-Date)

    $body = $payload | ConvertTo-Json 
    $deployment = Invoke-RestMethod "${deploymentEndpoint}api/deployments/${deploymentSubscriptionId}/${solutionTemplate}" -Headers $header -Method POST -Body $body -ContentType "application/json"

    Write-Host "New deployment:"
    $deployment

    $uniqueId = $deployment.uniqueId

    do {
        $deploymentDetails = MonitorAndPrintDeployment -Subscription $deploymentSubscriptionId -UniqueId $uniqueId
        $status = $deploymentDetails.deployment.status

        if ($status -like 'actionRequired') {
            Write-Host "Submitting input parameters..."

            $body = Get-Content -Raw -Path $manualInputParametersFile 
            $ignore = Invoke-RestMethod "${deploymentEndpoint}api/deployments/${deploymentSubscriptionId}/${uniqueId}" -Headers $header -Method PUT -Body $body -ContentType "application/json"
            Write-Host "Continuing provisioning..."
        }
    }
    while ($status -notlike 'failed' -and $status -notlike 'ready')

    $EndDateTime = (Get-Date)

    if ($status -notlike 'ready')
    {
        throw "Deployment failed."
    } else {
        $ElapsedSpan = New-TimeSpan -Start $StartDateTime -End $EndDateTime
        $ElapsedTime = "{0:HH:mm:ss}" -f ([datetime]$ElapsedSpan.Ticks)

        Write-Host "Deployment Time: $ElapsedTime"
    }

    Write-Host "Final output:"
    $deploymentDetails.provisioningSteps[-1].instructions.data
}
