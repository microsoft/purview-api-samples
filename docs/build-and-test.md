# Build & test (verify loop) — microsoft/purview-api-samples

This repo is a collection of independent samples with **no single build and no
CI**. The repo-level verify loop sanity-checks every sample without deploying
anything to a cloud.

## Repo-level verify

From the repo root:

```powershell
pwsh ./scripts/verify.ps1
```

`scripts/verify.ps1` runs these offline, non-deploying checks:

1. **PowerShell** — parses every `*.ps1` with the PowerShell language parser
   (syntax/tokenizer check; no execution).
2. **JSON** — validates each `*.json` sample (e.g. the Postman collection) parses.
3. **Python** — byte-compiles the Python sources (`py_compile`) when Python is
   available.
4. **.NET** — `dotnet build` of `dotnet/Desktop/Purview API Explorer.sln` when
   the .NET SDK is available (skipped with a warning if `dotnet` is missing or
   offline restore fails). Pass `-SkipDotnetBuild` to skip it explicitly.

The script exits non-zero if any required check fails.

## Per-sample commands

### AWSBedrock (Python Lambda + frontend)

```bash
# Lambda dependencies
cd AWSBedrock/lambda && pip install -r requirements.txt
# Run the frontend locally (serves http://localhost:8080)
cd AWSBedrock/frontend && python serve.py
```

Full deploy (AWS account required) is documented in
[`AWSBedrock/README.md`](../AWSBedrock/README.md).

### DLPforCustomAIApps (PowerShell)

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
./DLPforCustomAIApps/Create-DlpPolicyForCustomAIApps.ps1
```

### Foundry (PowerShell)

```powershell
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
./Foundry/EnableFoundryPurview.ps1
```

### Postman Collection

Import `Postman Collection/DSPM4AI_API_postman_collection.json` into Postman and
configure OAuth 2.0 as described in
[`Postman Collection/README.MD`](../Postman%20Collection/README.MD).

### dotnet/Desktop (.NET 8 WPF — Windows)

```powershell
dotnet build "dotnet/Desktop/Purview API Explorer.sln"
dotnet run --project "dotnet/Desktop/Purview API Explorer.csproj"
```

## Notes

- These samples call live Microsoft Purview / Graph / Azure / AWS endpoints and
  require real credentials to run end-to-end. The verify loop deliberately stops
  at static validation and local build so it is safe to run in CI or offline.
