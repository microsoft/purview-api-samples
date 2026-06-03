# Customer-shareable sample for creating a Microsoft Purview DLP policy
# for custom AI applications or agents.
#
# This sample:
# - Connects to Security & Compliance PowerShell
# - Optionally enables the DSPM for AI KYD collection policy
# - Creates an app-scoped DLP policy for one or more Entra app registrations
# - Creates a blocking rule for common sensitive information types
#
# Update the placeholder app IDs, names, and notification targets before use.

$ErrorActionPreference = "Stop"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

$EnableKydCollectionPolicy = $true
$EnableDlpPolicy = $true

$KydPolicyName = "DSPM for AI - Collection policy for enterprise AI apps"
$DlpPolicyName = "Contoso AI Apps - Block Sensitive Data"
$DlpRuleName = "Block common sensitive info in AI apps"

# Replace these placeholders with the customer's Entra app registration values.
$Applications = @(
    @{
        AppId = "11111111-1111-1111-1111-111111111111"
        AppName = "Contoso Expense Approval Agent"
    },
    @{
        AppId = "22222222-2222-2222-2222-222222222222"
        AppName = "Contoso HR Policy Agent"
    }
)

# Replace with valid recipients in the customer's tenant.
$AlertRecipients = @("SiteAdmin")
$IncidentRecipients = @("SiteAdmin")
$NotifyRecipients = @("SiteAdmin")

# Common sensitive information types to block.
$SensitiveTypes = @(
    @{ Name = "Credit Card Number"; minCount = "1" },
    @{ Name = "U.S. Social Security Number (SSN)"; minCount = "1" },
    @{ Name = "U.S. Bank Account Number"; minCount = "1" },
    @{ Name = "U.S. Individual Taxpayer Identification Number (ITIN)"; minCount = "1" },
    @{ Name = "Passport Number"; minCount = "1" },
    @{ Name = "IBAN"; minCount = "1" }
)

# -----------------------------------------------------------------------------
# Connect
# -----------------------------------------------------------------------------

Write-Host "Connecting to Security & Compliance PowerShell..." -ForegroundColor Cyan
Connect-IPPSSession

# -----------------------------------------------------------------------------
# Optional: Enable DSPM for AI KYD collection policy
# -----------------------------------------------------------------------------

if ($EnableKydCollectionPolicy) {
    $KydScenarioConfig = '{"Activities":["UploadText","DownloadText"],"EnforcementPlanes":["Application"],"SensitiveTypeIds":["All"],"IsIngestionEnabled":true}'
    $KydLocations = '[{"Workload":"Applications","Location":"<entra-group-object-id>","LocationSource":"Entra","LocationType":"Group","Inclusions":[{"Type":"Tenant","Identity":"All"}]}]'

    Write-Host "Ensuring KYD collection policy is enabled..." -ForegroundColor Yellow
    try {
        New-FeatureConfiguration `
            -FeatureScenario KnowYourData `
            -Name $KydPolicyName `
            -Mode Enable `
            -ScenarioConfig $KydScenarioConfig `
            -Locations $KydLocations | Out-Null

        Write-Host "KYD collection policy created." -ForegroundColor Green
    }
    catch {
        Write-Host "KYD collection policy may already exist. Updating it instead..." -ForegroundColor DarkYellow
        Set-FeatureConfiguration `
            -Identity $KydPolicyName `
            -ScenarioConfig $KydScenarioConfig | Out-Null

        Write-Host "KYD collection policy updated." -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# Build application-scoped DLP locations
# -----------------------------------------------------------------------------

$LocationsObject = foreach ($Application in $Applications) {
    @{
        Workload = "Applications"
        Location = $Application.AppId
        LocationDisplayName = $Application.AppName
        LocationSource = "Entra"
        LocationType = "Individual"
        Inclusions = @(
            @{
                Type = "Tenant"
                Identity = "All"
            }
        )
    }
}

$LocationsJson = $LocationsObject | ConvertTo-Json -Depth 6 -Compress

# -----------------------------------------------------------------------------
# Create or update the DLP policy
# -----------------------------------------------------------------------------

if ($EnableDlpPolicy) {
    Write-Host "Ensuring DLP policy exists..." -ForegroundColor Yellow

    $ExistingPolicy = Get-DlpCompliancePolicy -Identity $DlpPolicyName -ErrorAction SilentlyContinue
    if (-not $ExistingPolicy) {
        New-DlpCompliancePolicy `
            -Name $DlpPolicyName `
            -Comment "Blocks common sensitive information types in custom AI apps and agents." `
            -Locations $LocationsJson `
            -EnforcementPlanes @("Application") `
            -Mode Enable | Out-Null

        Write-Host "DLP policy created." -ForegroundColor Green
    }
    else {
        Set-DlpCompliancePolicy `
            -Identity $DlpPolicyName `
            -Locations $LocationsJson `
            -EnforcementPlanes @("Application") `
            -Mode Enable | Out-Null

        Write-Host "DLP policy updated." -ForegroundColor Green
    }

    Write-Host "Ensuring blocking DLP rule exists..." -ForegroundColor Yellow
    $ExistingRule = Get-DlpComplianceRule -Identity $DlpRuleName -ErrorAction SilentlyContinue

    $RuleParams = @{
        ContentContainsSensitiveInformation = $SensitiveTypes
        GenerateAlert = $AlertRecipients
        GenerateIncidentReport = $IncidentRecipients
        IncidentReportContent = @("Default", "Detections", "DetectionDetails", "MatchedItem", "RulesMatched", "Service", "Severity", "Title")
        NotifyUser = $NotifyRecipients
        ReportSeverityLevel = "High"
        RestrictAccess = @(
            @{ Setting = "UploadText"; Value = "Block" },
            @{ Setting = "DownloadText"; Value = "Block" }
        )
        StopPolicyProcessing = $true
        Comment = "Blocks prompts and responses containing common sensitive information types in custom AI apps."
    }

    if (-not $ExistingRule) {
        New-DlpComplianceRule `
            -Name $DlpRuleName `
            -Policy $DlpPolicyName `
            @RuleParams | Out-Null

        Write-Host "DLP rule created." -ForegroundColor Green
    }
    else {
        Set-DlpComplianceRule `
            -Identity $DlpRuleName `
            @RuleParams | Out-Null

        Write-Host "DLP rule updated." -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# Verification
# -----------------------------------------------------------------------------

Write-Host "Verification:" -ForegroundColor Cyan
Get-DlpCompliancePolicy -Identity $DlpPolicyName | Format-List Name, Mode, Locations
Get-DlpComplianceRule -Identity $DlpRuleName | Format-List Name, Policy, RestrictAccess, ReportSeverityLevel