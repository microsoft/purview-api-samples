# Conventions — microsoft/purview-api-samples

Observed conventions for this multi-sample repo. These describe what the samples
already do, so new contributions stay consistent. For the CLA and Code of
Conduct process, see [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Repository layout

- One top-level folder per sample (`AWSBedrock/`, `DLPforCustomAIApps/`,
  `Foundry/`, `Postman Collection/`, `dotnet/Desktop/`).
- Every sample ships a `README.md` (or `README.MD`) with Overview, Prerequisites,
  and run/test steps. New samples follow the same structure.
- Community-health and license files (`CONTRIBUTING.md`, `SECURITY.md`,
  `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `LICENSE.txt`) live at the repo root only.

## Secrets and configuration

- Never commit real tenant IDs, client IDs, client secrets, or cloud
  credentials. The root [`.gitignore`](../.gitignore) excludes `.env`, `.env.*`
  (except `.env.example`), `*.pem`, `*.key`, `*.pfx`, and `secrets.json`.
- Provide configuration as placeholders the user replaces (e.g.
  `<your-client-id>`, `<your-tenant-id>`), as in `AWSBedrock/.env.example` and
  the AWSBedrock README.
- Test data must use clearly fake sensitive values (e.g. `4111-1111-1111-1111`),
  matching the existing samples.

## PowerShell samples (`DLPforCustomAIApps`, `Foundry`, `AWSBedrock/*.ps1`)

- Target **PowerShell 7+** (Foundry also supports Windows PowerShell 5.1).
- Keep a clearly labeled `Configuration` block of variables near the top of the
  script for values users edit, as in `Create-DlpPolicyForCustomAIApps.ps1`.
- Use approved-verb cmdlet patterns (`New-*`/`Set-*`/`Get-*`/`Remove-*`) and
  print the resulting objects for verification.
- Surface optional behavior via parameters (e.g. Foundry's `-Output`,
  `-FilterOpenAiSubscriptions`).

## .NET sample (`dotnet/Desktop`)

- Target framework `net8.0-windows`, WPF, `Nullable` and `ImplicitUsings`
  enabled (see `Purview API Explorer.csproj`).
- Pin NuGet package versions explicitly in the `.csproj`.

## Python sample (`AWSBedrock/lambda`, `AWSBedrock/frontend`)

- Python 3.9+ (Lambda runtime 3.12). Declare dependencies in `requirements.txt`.
- Follow the existing fail-closed governance pattern (do not log full prompts or
  responses; make DLP decisions under the signed-in user's identity).

## Documentation style

- Markdown with a top-level `#` title, an Overview/What-it-does section, a
  Prerequisites section, and explicit run/test commands in fenced code blocks.
- Link to official `learn.microsoft.com` docs for APIs and cmdlets rather than
  duplicating their content.
