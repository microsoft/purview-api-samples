# AGENTS.md — Repo router for microsoft/purview-api-samples

> Short router / table of contents for humans and coding agents. This repo is a
> **multi-sample collection** of independent Microsoft Purview developer
> samples — there is no single buildable service. Each sample is self-contained
> with its own README, prerequisites, and run instructions.

## What this repo is

Samples that show how to call the Microsoft Purview APIs in Microsoft Graph to
support data security, compliance, and governance. See [`README.md`](./README.md)
for the canonical sample list.

## Samples (entry points)

| Sample | Stack | Entry point | Docs |
|--------|-------|-------------|------|
| AWSBedrock | Python 3.12 (AWS Lambda) + browser MSAL frontend + CloudFormation | [`AWSBedrock/lambda/lambda_function.py`](./AWSBedrock/lambda/lambda_function.py), [`AWSBedrock/frontend/serve.py`](./AWSBedrock/frontend/serve.py) | [`AWSBedrock/README.md`](./AWSBedrock/README.md) |
| DLPforCustomAIApps | PowerShell 7+ | [`DLPforCustomAIApps/Create-DlpPolicyForCustomAIApps.ps1`](./DLPforCustomAIApps/Create-DlpPolicyForCustomAIApps.ps1) | [`DLPforCustomAIApps/README.md`](./DLPforCustomAIApps/README.md) |
| Foundry | Windows PowerShell 5.1 / PowerShell 7+ (`Az.Accounts`) | [`Foundry/EnableFoundryPurview.ps1`](./Foundry/EnableFoundryPurview.ps1) | [`Foundry/README.md`](./Foundry/README.md) |
| Postman Collection | Postman / JSON | [`Postman Collection/DSPM4AI_API_postman_collection.json`](./Postman%20Collection/DSPM4AI_API_postman_collection.json) | [`Postman Collection/README.MD`](./Postman%20Collection/README.MD) |
| dotnet/Desktop | .NET 8 WPF (`net8.0-windows`) | [`dotnet/Desktop/Purview API Explorer.sln`](./dotnet/Desktop/) | [`dotnet/Desktop/README.MD`](./dotnet/Desktop/README.MD) |

## Conventions

See [`docs/conventions.md`](./docs/conventions.md) for observed code-style and
structure conventions, and [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the CLA and
Code of Conduct process.

## Verification / Definition of Done

This repo has no CI pipeline and no single build. Use the repo-level verify loop
to sanity-check all samples without deploying any of them:

- Run [`scripts/verify.ps1`](./scripts/verify.ps1) — parses every PowerShell
  script, byte-checks JSON samples, compiles the Python sources, and (when the
  .NET SDK is available) builds the WPF solution.
- See [`docs/build-and-test.md`](./docs/build-and-test.md) for the per-sample
  build/test/run commands (the documented form of the verify loop).

A change is **done** when `scripts/verify.ps1` passes and the touched sample's
own README steps still hold.

## PR conventions / telemetry (mandatory)

Every PR **and** ADO work item must follow the tagging rules in
[`.github/instructions/telemetry.instructions.md`](./.github/instructions/telemetry.instructions.md).
Apply the required labels and the description footer block on every turn.

## Guardrails for agents

- Keep changes scoped to a single sample where possible; do not refactor across
  samples in one PR.
- Never commit real tenant IDs, client secrets, or cloud credentials — see
  [`.gitignore`](./.gitignore) and `.env.example`. Use placeholders.
- Keep PRs small and reviewable (see
  [`.github/copilot-instructions.md`](./.github/copilot-instructions.md)).
