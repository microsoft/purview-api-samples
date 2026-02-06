# Azure RAI Policy - Purview Compliance Checker & Manager
# Checks subscriptions for Purview compliance and allows enable/disable

$ArmApiVersion = "2025-04-01"
$RaiApiVersion = "2025-10-01-preview"
$MaxThreads = 5

function Get-Token {
    $t = Get-AzAccessToken -ResourceUrl "https://management.azure.com/"
    if ($t.Token -is [securestring]) {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($t.Token))
    } else { $t.Token }
}

function Get-Headers { @{ Authorization = "Bearer $(Get-Token)"; "Content-Type" = "application/json" } }

function Test-PurviewEnabled($Policy) {
    if ($Policy.properties -and $Policy.properties.contentFilters) {
        $filters = $Policy.properties.contentFilters
        if (($filters | Where-Object { $_.source -in 'Prompt','Completion' } |
            Group-Object -Property source |
            ForEach-Object { $_.Group | Where-Object { $_.enabled -eq $true } }
        ).Count -eq 2) { return $true }
    }
    return $false
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
Write-Host "Found $($subs.Count) subscriptions"

function Get-SubscriptionStatus {
    Write-Host "Checking subscriptions..." -NoNewline
    $token = Get-Token
    $results = Invoke-ParallelCheck -Items $subs -Token $token -ApiVersion $RaiApiVersion -MaxThreads $MaxThreads
    Write-Host " Done`n" -ForegroundColor Green

    # Display results
    foreach ($r in ($results | Sort-Object Name)) {
        $status = if ($r.Error) { "[Error]"; $color = "Red" }
                  elseif ($r.Enabled) { "[Enabled]"; $color = "Green" }
                  else { "[Disabled]"; $color = "Yellow" }
        Write-Host "  $($r.Name) $status" -ForegroundColor $color
    }

    return $results | ForEach-Object { [pscustomobject]$_ }
}

$results = Get-SubscriptionStatus

# Summary
$enabledCount = ($results | Where-Object { $_.Enabled -eq $true }).Count
$disabledCount = ($results | Where-Object { $_.Enabled -eq $false }).Count
$errorCount = ($results | Where-Object { $_.Error }).Count
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
Write-Host "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount"

# Get actionable subscriptions
$actionable = $results | Where-Object { $null -eq $_.Error }
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
        $disabled = $results | Where-Object { $_.Enabled -eq $false -and $null -eq $_.Error }
        if ($disabled.Count -eq 0) { Write-Host "No disabled subscriptions." -ForegroundColor Yellow; break }
        Write-Host "`nDisabled subscriptions:"
        $disabled | ForEach-Object { Write-Host "  $($_.Name) - $($_.Id)" }
        $subId = Read-Host "`nSubscription ID to enable"
        $sub = $disabled | Where-Object { $_.Id -eq $subId }
        if (-not $sub) { Write-Host "Not found." -ForegroundColor Red; break }
        if ((Read-Host "Enable Purview for '$($sub.Name)'? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Enabling..." -NoNewline
            if (Set-PurviewPolicy $sub.Id $sub.Policy $true) { Write-Host " Done" -ForegroundColor Green }
        }
    }
    "2" {
        $enabledSubs = $results | Where-Object { $_.Enabled -eq $true }
        if ($enabledSubs.Count -eq 0) { Write-Host "No enabled subscriptions." -ForegroundColor Yellow; break }
        Write-Host "`nEnabled subscriptions:"
        $enabledSubs | ForEach-Object { Write-Host "  $($_.Name) - $($_.Id)" }
        $subId = Read-Host "`nSubscription ID to disable"
        $sub = $enabledSubs | Where-Object { $_.Id -eq $subId }
        if (-not $sub) { Write-Host "Not found." -ForegroundColor Red; break }
        if ((Read-Host "Disable Purview for '$($sub.Name)'? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Disabling..." -NoNewline
            if (Set-PurviewPolicy $sub.Id $sub.Policy $false) { Write-Host " Done" -ForegroundColor Green }
        }
    }
    "3" {
        $disabled = $results | Where-Object { $_.Enabled -eq $false -and $null -eq $_.Error }
        if ($disabled.Count -eq 0) { Write-Host "No disabled subscriptions." -ForegroundColor Yellow; break }
        if ((Read-Host "Enable Purview for ALL $($disabled.Count) disabled subscriptions? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Enabling $($disabled.Count) subscriptions..." -NoNewline
            $token = Get-Token
            $setResults = Invoke-ParallelSet -Items $disabled -Token $token -ApiVersion $RaiApiVersion -Enabled $true -MaxThreads $MaxThreads
            Write-Host " Done" -ForegroundColor Green
            $succeeded = ($setResults | Where-Object { $_.Success }).Count
            $failed = ($setResults | Where-Object { -not $_.Success }).Count
            Write-Host "  Succeeded: $succeeded | Failed: $failed"
            $setResults | Where-Object { -not $_.Success } | ForEach-Object { Write-Host "    $($_.Name): $($_.Error)" -ForegroundColor Red }
        }
    }
    "4" {
        $enabledSubs = $results | Where-Object { $_.Enabled -eq $true }
        if ($enabledSubs.Count -eq 0) { Write-Host "No enabled subscriptions." -ForegroundColor Yellow; break }
        if ((Read-Host "Disable Purview for ALL $($enabledSubs.Count) enabled subscriptions? (Y/n)").ToUpper() -in @("", "Y")) {
            Write-Host "Disabling $($enabledSubs.Count) subscriptions..." -NoNewline
            $token = Get-Token
            $setResults = Invoke-ParallelSet -Items $enabledSubs -Token $token -ApiVersion $RaiApiVersion -Enabled $false -MaxThreads $MaxThreads
            Write-Host " Done" -ForegroundColor Green
            $succeeded = ($setResults | Where-Object { $_.Success }).Count
            $failed = ($setResults | Where-Object { -not $_.Success }).Count
            Write-Host "  Succeeded: $succeeded | Failed: $failed"
            $setResults | Where-Object { -not $_.Success } | ForEach-Object { Write-Host "    $($_.Name): $($_.Error)" -ForegroundColor Red }
        }
    }
    "Q" { Write-Host "Exiting." }
    default { Write-Host "Invalid choice." -ForegroundColor Red }
}

if ($choice.ToUpper() -in @("1", "2", "3", "4")) {
    Write-Host "`n--- Refreshing ---" -ForegroundColor Cyan
    $results = Get-SubscriptionStatus
    $enabledCount = ($results | Where-Object { $_.Enabled -eq $true }).Count
    $disabledCount = ($results | Where-Object { $_.Enabled -eq $false }).Count
    $errorCount = ($results | Where-Object { $_.Error }).Count
    Write-Host "--- Updated Summary ---" -ForegroundColor Cyan
    Write-Host "Enabled: $enabledCount | Disabled: $disabledCount | Errors: $errorCount"
}

Write-Host "`n=== Complete ===" -ForegroundColor Cyan
return $results