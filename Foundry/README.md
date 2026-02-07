# Enable Purview for Azure AI Foundry — Script Guide

## Overview

The **EnableFoundryPurview.ps1** script is an interactive PowerShell tool that checks and manages [Microsoft Purview](https://learn.microsoft.com/purview/purview) compliance policies across your Azure subscriptions for **Azure AI Foundry**. It queries the **Responsible AI (RAI) Policy** API to determine whether Purview content-filtering is enabled on each subscription and provides options to enable or disable it in bulk or individually.

---

## What the Script Does

1. **Authenticates** to Azure using `Connect-AzAccount`.
2. **Enumerates** all subscriptions the signed-in user has access to.
3. **Checks** each subscription (in parallel) for an existing RAI Purview policy, reporting one of three statuses:
   - ✅ **Enabled** — Purview content filters are active for both Prompt and Completion.
   - ⚠️ **Disabled** — No Purview content filters are active.
   - ❌ **Error** — The subscription could not be queried (e.g., permission issues).
4. **Presents an interactive menu** with the following options:

   | Option | Description |
   |--------|-------------|
   | **1** | Enable Purview for a single disabled subscription |
   | **2** | Disable Purview for a single enabled subscription |
   | **3** | Enable Purview for **all** disabled subscriptions |
   | **4** | Disable Purview for **all** enabled subscriptions |
   | **Q** | Quit |

5. **Refreshes** and displays updated status after any change.

---

## Prerequisites

### 1. PowerShell

- **Windows PowerShell 5.1** or **PowerShell 7+** (cross-platform).

### 2. Azure PowerShell Module — `Az.Accounts`

The script imports `Az.Accounts` for authentication and token acquisition. Install it if you haven't already:

```powershell
Install-Module -Name Az.Accounts -Scope CurrentUser -Force
```

> **Tip:** If you already have the full **Az** module installed, `Az.Accounts` is included.

### 3. Azure Subscription(s)

You must have at least one Azure subscription. The script will enumerate every subscription visible to the authenticated identity.

---

## Permissions Required

The signed-in user must have **one** of the following roles assigned on each subscription they intend to manage:

### 1. Subscription Owner

The **Owner** role at the subscription scope is required to read/write RAI policies and enumerate subscriptions.

### 2. Azure AI Account Owner/User

The **Azure AI Account Owner** role must be assigned on the Foundry resource or subscription scope. This role grants full access to manage projects and resources, and allows conditionally assigning the Azure AI User role to other principals.

> For detailed permissions and guidance on assigning this role, see [Role-based access control for Microsoft Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/concepts/rbac-foundry?view=foundry-classic#built-in-roles).

---

## How to Run the Script

### Step 1 — Open PowerShell

Open a PowerShell terminal (Windows Terminal, VS Code integrated terminal, or the standalone PowerShell console).

### Step 2 — Navigate to the Script Directory

```powershell
cd "<path-to-repo>\Foundry"
```

### Step 3 — Run the Script

```powershell
.\EnableFoundryPurview.ps1
```

### Step 4 — Authenticate

A browser window (or device-code prompt) will appear for Azure sign-in via `Connect-AzAccount`. Sign in with an account that has the required permissions.

### Step 5 — Review Subscription Status

The script will list all subscriptions and their current Purview status:

```
=== Azure RAI Policy Purview Manager ===
Signing in... Done
Found 5 subscriptions
Checking subscriptions... Done

  Contoso Dev [Enabled]
  Contoso Prod [Disabled]
  Sandbox [Error]

--- Summary ---
Enabled: 1 | Disabled: 1 | Errors: 1
```

### Step 6 — Choose an Action

```
--- Options ---
[1] Enable Purview for a subscription
[2] Disable Purview for a subscription
[3] Enable ALL disabled subscriptions
[4] Disable ALL enabled subscriptions
[Q] Quit

Choice:
```

Follow the prompts to enable/disable Purview as needed. After the operation completes, the script refreshes and displays the updated status.

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---------|-------------|------------|
| `Import-Module Az.Accounts` fails | Module not installed | Run `Install-Module Az.Accounts -Scope CurrentUser` |
| Subscription shows **[Error]** | Insufficient permissions on that subscription | Verify the user has **Owner** on the subscription and **Azure AI Account Owner** on the Foundry resource |
| Enable/Disable fails with **403 Forbidden** | Missing Owner or Azure AI Account Owner role | Assign **Owner** at the subscription scope and **Azure AI Account Owner** on the Foundry resource |
| No subscriptions found | Account has no subscription access | Confirm the signed-in account has **Owner** on at least one subscription |

---

## API References

| API | Version Used | Documentation |
|-----|-------------|---------------|
| Azure Resource Manager — Subscriptions | `2025-04-01` | [List Subscriptions](https://learn.microsoft.com/rest/api/resources/subscriptions/list) |
| Cognitive Services — RAI Policy | `2025-10-01-preview` | [Cognitive Services REST API](https://learn.microsoft.com/rest/api/cognitiveservices/) |