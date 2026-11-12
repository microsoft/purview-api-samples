param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot '../EnableFoundryPurview.ps1')
)

$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'The sample has PowerShell syntax errors.' }

# Load only the real token/header functions, never the interactive main script.
foreach ($name in @('Get-Token', 'Get-Headers')) {
    $definition = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $false)
    if (-not $definition) { throw "Missing function: $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}

function Get-AzAccessToken {
    [CmdletBinding()]
    param($ResourceUrl)
    if ($ResourceUrl -cne 'https://management.azure.com/') { throw 'Unexpected token resource.' }
    $script:calls++
    [pscustomobject]@{ Token = $script:tokenValue }
}
function Connect-AzAccount { throw 'Unexpected sign-in attempt.' }
function Invoke-RestMethod { throw 'Unexpected REST call.' }
function Invoke-AzRestMethod { throw 'Unexpected ARM call.' }
function Invoke-MgGraphRequest { throw 'Unexpected Graph call.' }

$jwt = 'eyJhbGciOiJub25lIn0.eyJzdWIiOiJvZmZsaW5lIn0.offline'
$failures = 0
foreach ($case in @(
    @{ Name = 'SecureString JWT'; Text = $jwt; Secure = $true },
    @{ Name = 'plain-string JWT'; Text = $jwt; Secure = $false },
    @{ Name = 'SecureString Unicode'; Text = "offline-$([char]0x00e6)$([char]0x6f22)"; Secure = $true },
    @{ Name = 'empty SecureString'; Text = ''; Secure = $true }
)) {
    $script:calls = 0
    $script:tokenValue = if ($case.Secure) {
        if ($case.Text.Length) { ConvertTo-SecureString $case.Text -AsPlainText -Force }
        else { New-Object System.Security.SecureString }
    } else { $case.Text }
    try {
        $actual = Get-Token
        if ($actual -cne $case.Text) {
            throw "Token changed: expected length $($case.Text.Length), actual length $($actual.Length)."
        }
        $headers = Get-Headers
        if ($headers.Authorization -cne "Bearer $($case.Text)" -or $headers.'Content-Type' -cne 'application/json') {
            throw 'Incorrect request headers.'
        }
        if ($script:calls -ne 2) { throw 'Expected two stub token requests.' }
        Write-Host "PASS: $($case.Name)"
    } catch {
        $failures++
        Write-Host "FAIL: $($case.Name); $($_.Exception.Message)"
    }
}
if ($failures) { throw "$failures token-conversion regression case(s) failed." }
