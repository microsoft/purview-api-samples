# Microsoft Purview + Amazon Bedrock: Expense Approval Agent

A cross-cloud AI governance sample that pairs an **Amazon Bedrock** agent
(running in **AWS Lambda**) with **Microsoft Purview** Data Loss Prevention
(DLP) as the central policy decision point — even though the model and
compute live outside of Microsoft Azure.

> Companion sample for the blog post
> *"Microsoft Purview as the central policy engine for cross-cloud AI
> scenarios: Extending data protection to Amazon Web Services Bedrock
> Agents."*

## Why this matters

Most organizations are already multi-cloud. A team that standardizes on
Microsoft Purview for Exchange, SharePoint, Teams, and Microsoft 365
Copilot governance should not have to invent a second policy stack just
because an agent happens to run on AWS Bedrock or Google Vertex.

This sample shows that the *runtime* can be anywhere, while the *policy
decision* stays in Purview:

- A consistent layer for sensitive information types (credit cards, SSNs,
  financial data, custom SITs).
- A single governance plane that already extends across Microsoft 365.
- A familiar audit and compliance experience surfaced through Purview
  Data Security Posture Management (DSPM) for AI.
- Data-aware controls applied to *AI interactions* — not just storage.

## What the sample demonstrates

An **expense approval agent** that:

- Authenticates the user with **Microsoft Entra ID** using MSAL in the
  browser.
- Routes the prompt to an **AWS Lambda** function exposed via API Gateway.
- Uses the **On-Behalf-Of (OBO) flow** in the Lambda so Purview evaluates
  the request under the *signed-in user's* identity.
- Calls **Microsoft Purview** to evaluate the prompt for DLP violations
  *before* invoking the model.
- Calls **Amazon Bedrock (Nova 2 Lite)** if the prompt is allowed.
- Calls **Microsoft Purview** again to evaluate the model response
  *before* it is returned to the user.
- Renders a Purview evaluation badge alongside the answer.

## End-to-end flow

```
 ┌──────────────┐    1. Entra ID sign-in
 │   Browser    │◀──────────────────────────────────┐
 │  (MSAL SPA)  │                                   │
 └──────┬───────┘                                   │
        │ 2. POST /chat  (Bearer access_token)      │
        ▼                                           │
 ┌──────────────────────┐                           │
 │  API Gateway + AWS   │  3. OBO exchange ─▶ Microsoft Graph
 │      Lambda          │                           │
 │  (expense agent)     │  4. Purview processContent (uploadText)
 │                      │     └─ if blocked: return 403, no model call
 │                      │  5. Amazon Bedrock InvokeModel (Nova 2 Lite)
 │                      │  6. Purview processContent (downloadText)
 │                      │     └─ if blocked: return 403, no answer
 │                      │  7. Return {answer, purview verdict}
 └──────────────────────┘
```

Two enforcement points:

- **Inline prompt DLP** — block risky requests *before* they reach Bedrock.
- **Response DLP** — block sensitive content the model may generate.

Because evaluation runs as the signed-in user, group- and user-scoped
Purview policies behave as they do in any other M365 workload.

## Repository layout

```
AWSBedrock/
├── README.md             # this file
├── requirements.txt      # Python deps for the Lambda
├── lambda/
│   ├── handler.py        # Lambda entry point — orchestrates the 7-step flow
│   ├── purview_client.py # Microsoft Graph: protectionScopes + processContent
│   └── bedrock_client.py # boto3 wrapper around Bedrock InvokeModel (Nova 2 Lite)
├── frontend/
│   └── index.html        # MSAL SPA: chat UI + Purview verdict badge
└── infra/
    ├── README.md         # deployment options (SAM / CDK / Terraform)
    └── .env.example      # required configuration values
```

## Prerequisites

### Microsoft Entra / Purview

- Microsoft Purview licensing that includes DSPM for AI.
- An Entra app registration for this backend with delegated Graph
  permissions (admin consented):
  - `ProtectionScopes.Compute.All`
  - `Content.Process.All`
  - `ContentActivity.Write`
  - `User.Read`
- A client secret on the app registration (used by the Lambda for OBO).
- A Purview DLP policy that targets **AI apps** with `BlockAccess = true`
  for the sensitive information types you want to demo.

### AWS

- An AWS account with **Amazon Bedrock model access** for
  `amazon.nova-lite-v2:0` enabled in your chosen region.
- IAM execution role for the Lambda with:
  - `bedrock:InvokeModel` on the Nova model ARN.
  - CloudWatch Logs write.
- API Gateway (HTTP API is sufficient) in front of the Lambda.

### Frontend hosting

- Any static host (S3 + CloudFront, Azure Static Web Apps, GitHub Pages,
  or a local web server for development).
- The frontend's origin must be listed as a redirect URI on the Entra app
  registration.

## Quick start

See [infra/README.md](infra/README.md) for the full deploy walkthrough.
At a high level:

1. Register the Entra app, grant admin consent on the Graph permissions,
   and create a client secret.
2. Enable Bedrock Nova 2 Lite in your AWS region.
3. Copy `infra/.env.example` to `infra/.env` and fill in the values.
4. Package and deploy the Lambda + API Gateway (SAM / CDK / Terraform —
   your choice).
5. Configure the frontend `index.html` with your Entra tenant/client IDs
   and the API Gateway URL, then serve it.
6. Sign in with a tenant user, send a benign prompt, then send one that
   contains a regulated SIT (for example a fake credit-card number) and
   observe Purview block it.

## Verifying the governance evidence

After running the demo, the activity shows up in the **Purview portal**
under **Data Security Posture Management for AI** > Activity Explorer.
Each `processContent` call is logged with the policy verdict, the user's
identity, and a masked snippet of the content — even though the request
was served entirely from AWS.

## Related samples in this repository

- [Foundry/](../Foundry/) — equivalent governance pattern against
  Microsoft Foundry / Azure OpenAI.
- [Postman Collection/](../Postman%20Collection/) — raw Microsoft Graph
  calls for exploring the Purview APIs by hand.

## License

MIT — see [LICENSE.txt](../LICENSE.txt) at the repository root.
