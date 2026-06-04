# Microsoft Purview DLP for custom AI applications (PowerShell sample)

This sample helps you deploy a **Microsoft Purview Data Loss Prevention (DLP)
policy** that protects sensitive data flowing through your **own custom AI
applications and agents**. It is the PowerShell
counterpart to the guidance in
[Configure Microsoft Purview solutions in DSPM for AI for custom AI applications](https://learn.microsoft.com/en-us/purview/developer/configurepurview),
specifically the note:

> **Important.** To set up a new DLP policy in Microsoft Purview to test DLP
> integration, run the `New-DlpComplianceRule` cmdlet. For more information,
> see [New-DlpComplianceRule](https://learn.microsoft.com/powershell/module/exchange/new-dlpcompliancerule).

## What the sample does

The script in this folder, [`Create-DlpPolicyForCustomAIApps.ps1`](./Create-DlpPolicyForCustomAIApps.ps1):

1. Connects to Security & Compliance PowerShell (`Connect-IPPSSession`).
2. Builds a `Locations` JSON that scopes the policy to one or more **Microsoft
   Entra application registrations** via the `Application` enforcement plane.
3. Calls `New-DlpCompliancePolicy` (or `Set-DlpCompliancePolicy` if the policy
   already exists) to create the policy in `Enable` mode.
4. Calls `New-DlpComplianceRule` (or `Set-DlpComplianceRule`) to add a rule that:
   - Matches a configurable list of sensitive information types.
   - Blocks `UploadText` and `DownloadText` actions on a match.
   - Generates an alert, an incident report (severity High), and a user
     notification.
5. Prints the resulting policy and rule for verification.

> **Note.** `Application` replaces the deprecated `Entra` enforcement plane.
> Existing `Entra`-scoped policies continue to work; new policies should use
> `Application`.

## Prerequisites

- **PowerShell 7+** — see [Install PowerShell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell).
- The **ExchangeOnlineManagement** module:
  ```powershell
  Install-Module ExchangeOnlineManagement -Scope CurrentUser
  ```
- A Microsoft Purview role that can manage DLP policies (e.g. **Compliance
  Administrator** or **Compliance Data Administrator**).
- Each custom AI app **registered in Microsoft Entra ID**, with its
  **Application (client) ID** ready to drop into the script.
- Microsoft Purview Audit enabled in your tenant (see the [Enable Microsoft
  Purview Audit](https://learn.microsoft.com/en-us/purview/developer/configurepurview#enable-microsoft-purview-audit)
  section of the doc above).

## Customize the script

Open [`Create-DlpPolicyForCustomAIApps.ps1`](./Create-DlpPolicyForCustomAIApps.ps1)
and edit the values in the `Configuration` section near the top:

| Variable               | What to change                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------------- |
| `$DlpPolicyName`       | Friendly name shown in the Microsoft Purview portal.                                            |
| `$DlpRuleName`         | Friendly name for the rule under the policy.                                                    |
| `$PolicyMode`          | `Enable`, `TestWithNotifications`, `TestWithoutNotifications`, or `Disable`.                    |
| `$RestrictAction`      | `Block` to deny requests on a match, or `Audit` to log only.                                    |
| `$Applications`        | The list of Entra app registrations (one entry per AI app). Replace the placeholder GUIDs.      |
| `$AlertRecipients`     | Where alerts go. Use `SiteAdmin` or specific UPNs.                                              |
| `$IncidentRecipients`  | Where incident reports go.                                                                      |
| `$NotifyRecipients`    | Who gets the end-user notification on a block.                                                  |
| `$ReportSeverityLevel` | `Low`, `Medium`, or `High`.                                                                     |
| `$SensitiveTypes`      | The sensitive information types to detect. Add custom SITs or remove ones you don't need.       |

## Run the script

```powershell
# Sign in interactively when prompted; uses your Purview compliance role.
.\Create-DlpPolicyForCustomAIApps.ps1
```

The script prints the resulting `DlpCompliancePolicy` and `DlpComplianceRule`
for verification. You can also confirm in the Microsoft Purview portal under
**Data Loss Prevention → Policies**.

## Test the policy

After the policy is active, send a test prompt through your custom AI app that
contains a sample sensitive value (for example, a fake credit card number such
as `4111-1111-1111-1111`). With `$RestrictAction = "Block"`, the Microsoft
Purview API call from your app should return a block decision, your app should
deny the request, and you should see:

- A new **alert** in Microsoft Purview → **Data Loss Prevention → Alerts**.
- A new **incident report** delivered to `$IncidentRecipients`.
- Activity in **DSPM for AI → Activity explorer** for the matching app.

For a full end-to-end validation workflow, see
[Test Microsoft Purview configuration](https://learn.microsoft.com/en-us/purview/developer/testconfiguration).

## Clean up

```powershell
Remove-DlpComplianceRule   -Identity "Block sensitive info in custom AI apps"
Remove-DlpCompliancePolicy -Identity "Contoso Custom AI Apps - Block Sensitive Data"
```

## Related cmdlets and references

- [`New-DlpCompliancePolicy`](https://learn.microsoft.com/powershell/module/exchange/new-dlpcompliancepolicy)
- [`Set-DlpCompliancePolicy`](https://learn.microsoft.com/powershell/module/exchange/set-dlpcompliancepolicy)
- [`Get-DlpCompliancePolicy`](https://learn.microsoft.com/powershell/module/exchange/get-dlpcompliancepolicy)
- [`Remove-DlpCompliancePolicy`](https://learn.microsoft.com/powershell/module/exchange/remove-dlpcompliancepolicy)
- [`New-DlpComplianceRule`](https://learn.microsoft.com/powershell/module/exchange/new-dlpcompliancerule)
- [`Set-DlpComplianceRule`](https://learn.microsoft.com/powershell/module/exchange/set-dlpcompliancerule)
- [`Connect-IPPSSession`](https://learn.microsoft.com/powershell/exchange/connect-to-scc-powershell)
- [Configure Microsoft Purview solutions in DSPM for AI for custom AI applications](https://learn.microsoft.com/en-us/purview/developer/configurepurview)
- [Microsoft Purview developer platform](https://learn.microsoft.com/en-us/purview/developer/)
