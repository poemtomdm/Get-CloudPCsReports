param (
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [int]$Days,
    [switch]$Json  
)

$global:tenant = $tenantId
$global:clientId = $clientId
$global:clientSecret = $clientSecret
$SecuredPasswordPassword = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$ClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $SecuredPasswordPassword

Connect-MgGraph -TenantId $tenant -ClientSecretCredential $ClientSecretCredential -NoWelcome

$allDevices = @()
# Ensure $dateref is an integer
$days = [int]$days  

# Check if dateref is provided, otherwise use default 7 days
if (-not $days) {
    $daterefFormatted = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")
} else {
    $daterefFormatted = (Get-Date).AddDays(-$days).ToString("yyyy-MM-ddTHH:mm:ssZ")
}

$nextLink = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/cloudPCs"

# Fetch all devices
while (![string]::IsNullOrEmpty($nextLink)) {
    $response = Invoke-MgGraphRequest -Method GET -Uri "$nextLink"
    $allDevices += $response.value
    $nextLink = $response.'@odata.nextLink'
    Write-Host $nextLink
}

$allReportData = @()

foreach ($device in $allDevices) {

    $cloudpcid = $device.id
    $cloudpcname = $device.managedDeviceName
    $upn = $device.userPrincipalName
    
    $uri = "https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/reports/getRemoteConnectionHistoricalReports" 
    $body = @{
        filter = "CloudPcId eq '$cloudpcid' and SignInDateTime gt datetime'$daterefFormatted '"
        select = @( # Use an array for 'select'
            "UsageInHour"
        )
        top = 100
        skip = 0
    } | ConvertTo-Json -Compress -Depth 5 #-Compress removes extra whitespace
    
    $tempFilePath = [System.IO.Path]::GetTempFileName()

    $response = Invoke-MgGraphRequest -Method post -Uri $uri -Body $body -OutputFilePath $tempFilePath
    
    # Read the content of the temporary file
    $responseContent = Get-Content -Path $tempFilePath -Raw | ConvertFrom-Json
    $sum = 0
    foreach ($valueArray in $responseContent.values) {
        foreach ($value in $valueArray) {
            $sum += [double]$value
        }
    }
    $reportdata = [PSCustomObject]@{
        CloudPCName = $cloudpcname
        UPN = $upn
        UsageInHours = $sum
    }
    $allReportData += $reportdata
}

# Output results based on the -Table switch
if ($Json) {
    return $allReportData | ConvertTo-Json -Depth 5 
} else {
    return $allReportData | Format-Table -AutoSize
}
