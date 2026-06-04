# Microsoft Purview Developer Platform

This repo contains samples that developers can use to learn how to call the Purview APIs in Microsoft Graph from their applications, to support data security, compliance and governance.

## Samples in this repo

| Sample | Description |
|--------|-------------|
| [AWSBedrock](./AWSBedrock) | A cross-cloud AI agent on AWS Lambda using Amazon Bedrock (Nova 2 Lite) and the Microsoft Agent Framework SDK with Purview middleware. Demonstrates applying Microsoft Purview DLP to every prompt and model response in a multicloud AI workload, with a browser-based MSAL chat frontend and Entra ID On-Behalf-Of authentication. |
| [DLPforCustomAIApps](./DLPforCustomAIApps) | A PowerShell script ([`Create-DlpPolicyForCustomAIApps.ps1`](./DLPforCustomAIApps/Create-DlpPolicyForCustomAIApps.ps1)) that creates a Microsoft Purview DLP policy scoped to one or more Microsoft Entra application registrations via the `Application` enforcement plane, so custom AI apps and agents can be protected with DLP rules that block `UploadText`/`DownloadText` on sensitive info type matches. |
| [Foundry](./Foundry) | An interactive PowerShell script ([`EnableFoundryPurview.ps1`](./Foundry/EnableFoundryPurview.ps1)) that checks and manages Microsoft Purview Responsible AI (RAI) content-filtering policies for Azure AI Foundry across all subscriptions a user has access to, with bulk and per-subscription enable/disable options. |
| [Postman Collection](./Postman%20Collection) | A Postman collection for exercising the Purview Graph APIs, including `ProtectionScopes` (user-delegated and application auth) and `ProcessContent` for prompts and responses (sync user-delegated and async application auth). |
| [dotnet/Desktop](./dotnet/Desktop) | A .NET 8 WPF desktop sample (`Purview API Explorer`) that shows the basics of calling the Microsoft Purview APIs in Microsoft Graph, using the Windows authentication broker by default with an option to sign in as a different user. |


