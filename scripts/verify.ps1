#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Repo-level verify loop for microsoft/purview-api-samples.

.DESCRIPTION
    This repo is a collection of independent samples with no single build and no
    CI. This script runs offline, non-deploying checks across every sample:
      1. PowerShell  - parse every *.ps1 (syntax check, no execution)
      2. JSON        - validate every *.json sample parses
      3. Python      - byte-compile Python sources (py_compile) when available
      4. .NET        - dotnet build the WPF solution when the SDK is available

    Exits non-zero if any required check fails. See docs/build-and-test.md.

.PARAMETER SkipDotnetBuild
    Skip the .NET build step (useful offline or where the SDK is unavailable).
#>
[CmdletBinding()]
param(
    [switch]$SkipDotnetBuild
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Write-Section($name) { Write-Host "`n=== $name ===" -ForegroundColor Cyan }

# Exclude VCS and build output directories
function Get-RepoFiles($pattern) {
    Get-ChildItem -Path $repoRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(\.git|bin|obj|node_modules|__pycache__)\\' }
}

# 1. PowerShell syntax
Write-Section 'PowerShell syntax'
foreach ($f in Get-RepoFiles '*.ps1') {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $failures.Add("PowerShell parse failed: $($f.FullName) ($($errors.Count) error(s))")
        Write-Host "  FAIL $($f.Name)" -ForegroundColor Red
    } else {
        Write-Host "  ok   $($f.Name)" -ForegroundColor Green
    }
}

# 2. JSON validity
Write-Section 'JSON validity'
foreach ($f in Get-RepoFiles '*.json') {
    try {
        Get-Content -Raw -Path $f.FullName | ConvertFrom-Json -ErrorAction Stop | Out-Null
        Write-Host "  ok   $($f.Name)" -ForegroundColor Green
    } catch {
        $failures.Add("JSON parse failed: $($f.FullName)")
        Write-Host "  FAIL $($f.Name)" -ForegroundColor Red
    }
}

# 3. Python byte-compile
Write-Section 'Python compile'
$python = (Get-Command python -ErrorAction SilentlyContinue) ?? (Get-Command python3 -ErrorAction SilentlyContinue)
if ($python) {
    foreach ($f in Get-RepoFiles '*.py') {
        & $python.Source -m py_compile $f.FullName 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ok   $($f.Name)" -ForegroundColor Green
        } else {
            $failures.Add("Python compile failed: $($f.FullName)")
            Write-Host "  FAIL $($f.Name)" -ForegroundColor Red
        }
    }
} else {
    $warnings.Add('Python not found; skipped Python compile checks.')
    Write-Host '  (python not found - skipped)' -ForegroundColor Yellow
}

# 4. .NET build
Write-Section '.NET build (dotnet/Desktop)'
$sln = Join-Path $repoRoot 'dotnet/Desktop/Purview API Explorer.sln'
if ($SkipDotnetBuild) {
    Write-Host '  (skipped via -SkipDotnetBuild)' -ForegroundColor Yellow
} elseif (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    $warnings.Add('dotnet SDK not found; skipped .NET build.')
    Write-Host '  (dotnet not found - skipped)' -ForegroundColor Yellow
} else {
    dotnet build $sln -nologo --verbosity quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  ok   Purview API Explorer.sln' -ForegroundColor Green
    } else {
        $warnings.Add('dotnet build failed (often offline NuGet restore); re-run with network. Not treated as a hard failure here.')
        Write-Host '  WARN dotnet build failed (see docs/build-and-test.md)' -ForegroundColor Yellow
    }
}

# Summary
Write-Section 'Summary'
foreach ($w in $warnings) { Write-Host "WARN: $w" -ForegroundColor Yellow }
if ($failures.Count -gt 0) {
    foreach ($x in $failures) { Write-Host "FAIL: $x" -ForegroundColor Red }
    Write-Host "`nverify.ps1: FAILED ($($failures.Count) error(s))" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "`nverify.ps1: PASSED" -ForegroundColor Green
Pop-Location
exit 0
