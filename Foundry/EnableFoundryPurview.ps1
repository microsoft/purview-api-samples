# Azure RAI Policy - Purview Compliance Checker & Manager
# Checks subscriptions for Purview compliance and allows enable/disable

param(
    [Parameter(Mandatory = $false)]
    [string]$Output,

    [switch]$FilterOpenAiSubscriptions
)

$ArmApiVersion = "2025-04-01"
$RaiApiVersion = "2025-10-01-preview"
$ResourceGraphApiVersion = "2021-03-01"
$MaxThreads = 5
$OutputThreshold = 50
$OutputFilePath = $null

function Resolve-OutputFile {
    param([string]$OutputDir, [int]$SubCount)

    $useFile = $false
    $dir = $null

    if ($OutputDir) {
        $useFile = $true
        $dir = $OutputDir
    } elseif ($SubCount -gt $script:OutputThreshold) {
        $useFile = $true
        $dir = (Get-Location).Path
    }

    if ($useFile) {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        return Join-Path $dir "PurviewResults_$timestamp.txt"
    }
    return $null
}

function Write-Output-Line {
    param([string]$Text, [string]$FilePath)
    if ($FilePath) {
        $Text | Out-File -FilePath $FilePath -Append -Encoding UTF8
    } else {
        Write-Host $Text
    }
}

function Get-Token {
    $t = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
    if ($t.Token -is [securestring]) {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($t.Token))
    } else { $t.Token }
}

function Get-Headers { @{ Authorization = "Bearer $(Get-Token)"; "Content-Type" = "application/json" } }

function Get-OpenAiSubscriptionIds {
    param([string]$Token)

    $uri = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=$ResourceGraphApiVersion"
    $headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
    $body = @{
        query = "Resources | where type =~ 'microsoft.cognitiveservices/accounts' and kind =~ 'OpenAI' | distinct subscriptionId"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body -ErrorAction Stop
    return @($response.data | ForEach-Object { $_.subscriptionId })
}

# Scriptblock subscription check
$CheckSubscriptionScript = {
    param($SubId, $SubName, $Token, $ApiVersion)

    $headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
    $uri = "https://management.azure.com/subscriptions/$SubId/providers/Microsoft.CognitiveServices/raiPolicy?api-version=$ApiVersion"

    $result = @{ Id = $SubId; Name = $SubName; Policy = $null; Enabled = $null; Error = $null }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
        $result.Policy = $response

        # Inline Test-PurviewEnabled logic
        $enabled = $false
        if ($response.properties -and $response.properties.contentFilters) {
            $filters = $response.properties.contentFilters
            $promptEnabled = $filters | Where-Object { $_.source -eq 'Prompt' -and $_.enabled -eq $true }
            $completionEnabled = $filters | Where-Object { $_.source -eq 'Completion' -and $_.enabled -eq $true }
            $enabled = ($promptEnabled -and $completionEnabled)
        }
        $result.Enabled = $enabled
    } catch {
        if ($_.Exception.Message -match "404|NotFound") {
            $result.Enabled = $false
        } else {
            $result.Error = $_.Exception.Message
        }
    }
    return $result
}

# Scriptblock for setting purview policy
$SetPolicyScript = {
    param($SubId, $SubName, $Token, $ApiVersion, $ExistingPolicyJson, [bool]$Enabled)

    $headers = @{ Authorization = "Bearer $Token"; "Content-Type" = "application/json" }
    $uri = "https://management.azure.com/subscriptions/$SubId/providers/Microsoft.CognitiveServices/raiPolicy?api-version=$ApiVersion"

    $result = @{ Id = $SubId; Name = $SubName; Success = $false; Error = $null }

    # Build policy
    if ($ExistingPolicyJson) {
        $ExistingPolicy = $ExistingPolicyJson | ConvertFrom-Json
        $filters = @($ExistingPolicy.properties.contentFilters | Where-Object { $_.name -ne 'purview' })
        $policy = @{
            type = if ($ExistingPolicy.properties.type) { $ExistingPolicy.properties.type } else { "UserManaged" }
            mode = if ($ExistingPolicy.properties.mode) { $ExistingPolicy.properties.mode } else { "Blocking" }
            basePolicyName = if ($ExistingPolicy.properties.basePolicyName) { $ExistingPolicy.properties.basePolicyName } else { "PurviewEnablement" }
            contentFilters = $filters + @(
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Prompt" }
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Completion" }
            )
        }
    } else {
        $policy = @{
            type = "UserManaged"; mode = "Blocking"; basePolicyName = "PurviewEnablement"
            contentFilters = @(
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Prompt" }
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Completion" }
            )
        }
    }

    try {
        Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body ($policy | ConvertTo-Json -Depth 10) -ErrorAction Stop | Out-Null
        $result.Success = $true
    } catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

# Parallel execution for checking subscriptions
function Invoke-ParallelCheck {
    param($Items, $Token, $ApiVersion, $MaxThreads = 10)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
    $runspacePool.Open()

    $jobs = @()
    foreach ($item in $Items) {
        $ps = [powershell]::Create().AddScript($CheckSubscriptionScript)
        $ps.AddParameter("SubId", $item.subscriptionId) | Out-Null
        $ps.AddParameter("SubName", $item.displayName) | Out-Null
        $ps.AddParameter("Token", $Token) | Out-Null
        $ps.AddParameter("ApiVersion", $ApiVersion) | Out-Null
        $ps.RunspacePool = $runspacePool
        $jobs += @{ Pipe = $ps; Handle = $ps.BeginInvoke() }
    }

    $results = @()
    foreach ($job in $jobs) {
        $results += $job.Pipe.EndInvoke($job.Handle)
        $job.Pipe.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()
    return $results
}

# Parallel execution for setting policies
function Invoke-ParallelSet {
    param($Items, $Token, $ApiVersion, [bool]$Enabled, $MaxThreads = 10)

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
    $runspacePool.Open()

    $jobs = @()
    foreach ($item in $Items) {
        $ps = [powershell]::Create().AddScript($SetPolicyScript)
        $ps.AddParameter("SubId", $item.Id) | Out-Null
        $ps.AddParameter("SubName", $item.Name) | Out-Null
        $ps.AddParameter("Token", $Token) | Out-Null
        $ps.AddParameter("ApiVersion", $ApiVersion) | Out-Null
        $ps.AddParameter("ExistingPolicyJson", $(if ($item.Policy) { $item.Policy | ConvertTo-Json -Depth 10 } else { $null })) | Out-Null
        $ps.AddParameter("Enabled", $Enabled) | Out-Null
        $ps.RunspacePool = $runspacePool
        $jobs += @{ Pipe = $ps; Handle = $ps.BeginInvoke() }
    }

    $results = @()
    foreach ($job in $jobs) {
        $results += $job.Pipe.EndInvoke($job.Handle)
        $job.Pipe.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()
    return $results
}

function Set-PurviewPolicy($SubId, $ExistingPolicy, [bool]$Enabled) {
    $uri = "https://management.azure.com/subscriptions/$SubId/providers/Microsoft.CognitiveServices/raiPolicy?api-version=$RaiApiVersion"

    if ($ExistingPolicy) {
        $filters = @($ExistingPolicy.properties.contentFilters | Where-Object { $_.name -ne 'purview' })
        $policy = @{
            type = if ($ExistingPolicy.properties.type) { $ExistingPolicy.properties.type } else { "UserManaged" }
            mode = if ($ExistingPolicy.properties.mode) { $ExistingPolicy.properties.mode } else { "Blocking" }
            basePolicyName = if ($ExistingPolicy.properties.basePolicyName) { $ExistingPolicy.properties.basePolicyName } else { "PurviewEnablement" }
            contentFilters = $filters + @(
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Prompt" }
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Completion" }
            )
        }
    } else {
        $policy = @{
            type = "UserManaged"; mode = "Blocking"; basePolicyName = "PurviewEnablement"
            contentFilters = @(
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Prompt" }
                @{ name = "purview"; enabled = $Enabled; blocking = $true; source = "Completion" }
            )
        }
    }

    try {
        Invoke-RestMethod -Method POST -Uri $uri -Headers (Get-Headers) -Body ($policy | ConvertTo-Json -Depth 10) -ErrorAction Stop
        $true
    } catch { Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red; $false }
}

# --- Main ---
Import-Module Az.Accounts -ErrorAction Stop
Write-Host "`n=== Azure RAI Policy Purview Manager ===" -ForegroundColor Cyan
Write-Host "Signing in..." -NoNewline
Connect-AzAccount | Out-Null
Write-Host " Done" -ForegroundColor Green

# Get token and subscriptions
$token = Get-Token
$subs = (Invoke-RestMethod -Uri "https://management.azure.com/subscriptions?api-version=$ArmApiVersion" -Headers (Get-Headers)).value
Write-Host "Found $($subs.Count) total subscriptions"

# Filter to subscriptions with OpenAI resources if specified
if ($FilterOpenAiSubscriptions) {
    Write-Host "Filtering to subscriptions with OpenAI resources..." -NoNewline
    $matchedSubIds = Get-OpenAiSubscriptionIds -Token $token
    $subs = @($subs | Where-Object { $_.subscriptionId -in $matchedSubIds })
    Write-Host " Done" -ForegroundColor Green
    Write-Host "Matched $($subs.Count) subscriptions with OpenAI resources" -ForegroundColor Yellow
    if ($subs.Count -eq 0) {
        Write-Host "No subscriptions contain OpenAI resources. Exiting." -ForegroundColor Red
        return
    }
}

# Resolve output file
$OutputFilePath = Resolve-OutputFile -OutputDir $Output -SubCount $subs.Count
if ($OutputFilePath) {
    Write-Host "Results will be written to: $OutputFilePath" -ForegroundColor Cyan
    "=== Azure RAI Policy Purview Manager ===" | Out-File -FilePath $OutputFilePath -Encoding UTF8
    "Run Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $OutputFilePath -Append -Encoding UTF8
    "Subscription Count: $($subs.Count)" | Out-File -FilePath $OutputFilePath -Append -Encoding UTF8
    "" | Out-File -FilePath $OutputFilePath -Append -Encoding UTF8
}

function Get-SubscriptionStatus {
    param([string]$Label = "Checking")
    Write-Host "$Label subscriptions..." -NoNewline
    $token = Get-Token
    $results = Invoke-ParallelCheck -Items $subs -Token $token -ApiVersion $RaiApiVersion -MaxThreads $MaxThreads
    Write-Host " Done`n" -ForegroundColor Green

    # Display results
    if ($OutputFilePath) {
        Write-Output-Line "--- Subscription Status ($Label) ---" $OutputFilePath
    }
    foreach ($r in ($results | Sort-Object Name)) {
        $status = if ($r.Error) { "[Error]" }
                  elseif ($r.Enabled) { "[Enabled]" }
                  else { "[Disabled]" }

        if ($OutputFilePath) {
            Write-Output-Line "  $($r.Name) $status" $OutputFilePath
        } else {
            $color = if ($r.Error) { "Red" } elseif ($r.Enabled) { "Green" } else { "Yellow" }
            Write-Host "  $($r.Name) $status" -ForegroundColor $color
        }
    }

    return $results | ForEach-Object { [pscustomobject]$_ }
}

$results = Get-SubscriptionStatus

# Summary
$enabledCount = @($results | Where-Object { $_.Enabled -eq $true }).Count
$disabledCount = @($results | Where-Object { $_.Enabled -eq $false }).Count
$errorCount = @($results | Where-Object { $_.Error }).Count
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount"
if ($OutputFilePath) {
    Write-Output-Line "`n--- Summary ---" $OutputFilePath
    Write-Output-Line "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount" $OutputFilePath
}

# Get actionable subscriptions
$actionable = @($results | Where-Object { $null -eq $_.Error })
if ($actionable.Count -eq 0) { Write-Host "`nNo subscriptions available for changes."; return $results }

# Options menu
Write-Host "`n--- Options ---" -ForegroundColor Cyan
Write-Host "[1] Enable Purview for a subscription"
Write-Host "[2] Disable Purview for a subscription"
Write-Host "[3] Enable ALL disabled subscriptions"
Write-Host "[4] Disable ALL enabled subscriptions"
Write-Host "[Q] Quit"

$choice = Read-Host "`nChoice"
switch ($choice.ToUpper()) {
    "1" {
        $disabled = @($results | Where-Object { $_.Enabled -eq $false -and $null -eq $_.Error })
        if ($disabled.Count -eq 0) { Write-Host "No disabled subscriptions." -ForegroundColor Yellow; break }
        Write-Host "`nDisabled subscriptions:"
        $disabled | ForEach-Object {
            Write-Host "  $($_.Name) - $($_.Id)"
            if ($OutputFilePath) { Write-Output-Line "  $($_.Name) - $($_.Id)" $OutputFilePath }
        }
        $subId = Read-Host "`nSubscription ID to enable"
        $sub = $disabled | Where-Object { $_.Id -eq $subId }
        if (-not $sub) { Write-Host "Not found." -ForegroundColor Red; break }
        if ((Read-Host "Enable Purview for '$($sub.Name)'? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Enabling..." -NoNewline
            if (Set-PurviewPolicy $sub.Id $sub.Policy $true) {
                Write-Host " Done" -ForegroundColor Green
                if ($OutputFilePath) { Write-Output-Line "Enabled: $($sub.Name) ($($sub.Id))" $OutputFilePath }
            }
        }
    }
    "2" {
        $enabledSubs = @($results | Where-Object { $_.Enabled -eq $true })
        if ($enabledSubs.Count -eq 0) { Write-Host "No enabled subscriptions." -ForegroundColor Yellow; break }
        Write-Host "`nEnabled subscriptions:"
        $enabledSubs | ForEach-Object {
            Write-Host "  $($_.Name) - $($_.Id)"
            if ($OutputFilePath) { Write-Output-Line "  $($_.Name) - $($_.Id)" $OutputFilePath }
        }
        $subId = Read-Host "`nSubscription ID to disable"
        $sub = $enabledSubs | Where-Object { $_.Id -eq $subId }
        if (-not $sub) { Write-Host "Not found." -ForegroundColor Red; break }
        if ((Read-Host "Disable Purview for '$($sub.Name)'? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Disabling..." -NoNewline
            if (Set-PurviewPolicy $sub.Id $sub.Policy $false) {
                Write-Host " Done" -ForegroundColor Green
                if ($OutputFilePath) { Write-Output-Line "Disabled: $($sub.Name) ($($sub.Id))" $OutputFilePath }
            }
        }
    }
    "3" {
        $disabled = @($results | Where-Object { $_.Enabled -eq $false -and $null -eq $_.Error })
        if ($disabled.Count -eq 0) { Write-Host "No disabled subscriptions." -ForegroundColor Yellow; break }
        if ((Read-Host "Enable Purview for ALL $($disabled.Count) disabled subscriptions? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Enabling $($disabled.Count) subscriptions..." -NoNewline
            $token = Get-Token
            $setResults = Invoke-ParallelSet -Items $disabled -Token $token -ApiVersion $RaiApiVersion -Enabled $true -MaxThreads $MaxThreads
            Write-Host " Done" -ForegroundColor Green
            $succeeded = @($setResults | Where-Object { $_.Success }).Count
            $failed = @($setResults | Where-Object { -not $_.Success }).Count
            Write-Host "  Succeeded: $succeeded | Failed: $failed"
            $setResults | Where-Object { -not $_.Success } | ForEach-Object { Write-Host "    $($_.Name): $($_.Error)" -ForegroundColor Red }
            if ($OutputFilePath) {
                Write-Output-Line "`n--- Enable ALL Results ---" $OutputFilePath
                Write-Output-Line "Succeeded: $succeeded | Failed: $failed" $OutputFilePath
                $setResults | ForEach-Object {
                    $status = if ($_.Success) { "Success" } else { "Failed: $($_.Error)" }
                    Write-Output-Line "  $($_.Name) ($($_.Id)): $status" $OutputFilePath
                }
            }
        }
    }
    "4" {
        $enabledSubs = @($results | Where-Object { $_.Enabled -eq $true })
        if ($enabledSubs.Count -eq 0) { Write-Host "No enabled subscriptions." -ForegroundColor Yellow; break }
        if ((Read-Host "Disable Purview for ALL $($enabledSubs.Count) enabled subscriptions? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Disabling $($enabledSubs.Count) subscriptions..." -NoNewline
            $token = Get-Token
            $setResults = Invoke-ParallelSet -Items $enabledSubs -Token $token -ApiVersion $RaiApiVersion -Enabled $false -MaxThreads $MaxThreads
            Write-Host " Done" -ForegroundColor Green
            $succeeded = @($setResults | Where-Object { $_.Success }).Count
            $failed = @($setResults | Where-Object { -not $_.Success }).Count
            Write-Host "  Succeeded: $succeeded | Failed: $failed"
            $setResults | Where-Object { -not $_.Success } | ForEach-Object { Write-Host "    $($_.Name): $($_.Error)" -ForegroundColor Red }
            if ($OutputFilePath) {
                Write-Output-Line "`n--- Disable ALL Results ---" $OutputFilePath
                Write-Output-Line "Succeeded: $succeeded | Failed: $failed" $OutputFilePath
                $setResults | ForEach-Object {
                    $status = if ($_.Success) { "Success" } else { "Failed: $($_.Error)" }
                    Write-Output-Line "  $($_.Name) ($($_.Id)): $status" $OutputFilePath
                }
            }
        }
    }
    "Q" { Write-Host "Exiting." }
    default { Write-Host "Invalid choice." -ForegroundColor Red }
}

if ($choice.ToUpper() -in @("1", "2", "3", "4")) {
    Write-Host "`n--- Refreshing ---" -ForegroundColor Cyan
    if ($OutputFilePath) { Write-Output-Line "`n--- Refreshed Status ---" $OutputFilePath }
    $results = Get-SubscriptionStatus -Label "Refreshing"
    $enabledCount = @($results | Where-Object { $_.Enabled -eq $true }).Count
    $disabledCount = @($results | Where-Object { $_.Enabled -eq $false }).Count
    $errorCount = @($results | Where-Object { $_.Error }).Count
    Write-Host "--- Updated Summary ---" -ForegroundColor Cyan
    Write-Host "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount"
    if ($OutputFilePath) {
        Write-Output-Line "`n--- Updated Summary ---" $OutputFilePath
        Write-Output-Line "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount" $OutputFilePath
    }
}

Write-Host "`n=== Complete ===" -ForegroundColor Cyan
if ($OutputFilePath) {
    Write-Output-Line "`n=== Complete ===" $OutputFilePath
    Write-Host "Full results saved to: $OutputFilePath" -ForegroundColor Cyan
}
return $results