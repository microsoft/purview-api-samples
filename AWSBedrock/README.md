# AWS Bedrock Agent with Microsoft Purview DLP Governance

A cross-cloud AI agent that demonstrates how to apply **Microsoft Purview Data Loss Prevention (DLP)** policies to an **Amazon Bedrock** AI workload running on AWS Lambda. This solution shows that data security governance does not need to stop at the cloud boundary.

The agent is built on the [**Microsoft Agent Framework SDK**](https://github.com/microsoft/agent-framework) (`agent-framework-core`) and uses the framework's [**Purview middleware**](https://github.com/microsoft/agent-framework) (`agent-framework-purview`) to insert DLP evaluation directly into the agent's request and response pipeline — so every prompt and model response is inspected by Microsoft Purview before it reaches Amazon Bedrock or the end user.

## Overview

This repository contains a complete, working example of a multicloud AI governance pattern:

- **Frontend**: Browser-based chat UI with Microsoft Entra ID authentication (MSAL)
- **Compute**: AWS Lambda
- **Agent runtime**: Microsoft Agent Framework SDK (`agent-framework-core`)
- **Governance middleware**: Microsoft Agent Framework Purview middleware (`agent-framework-purview`)
- **Model**: Amazon Bedrock (Nova 2 Lite)
- **Identity**: Microsoft Entra ID via On-Behalf-Of (OBO) flow
- **Governance**: Microsoft Purview Data Loss Prevention

Every user prompt and model response is evaluated by Purview DLP using the signed-in user's identity. If sensitive information is detected, the request or response is blocked inline.

## Why this matters

Organizations building AI agents often face a governance challenge: the agent might run on AWS, but the data security policies live in Microsoft Purview. This solution proves that Purview can serve as a **central policy engine** for multicloud AI workloads, without requiring the compute or models to run in Azure.

### Key benefits

- **Unified governance**: One set of policies protects both Microsoft 365 and cross-cloud AI interactions
- **User-centric enforcement**: DLP decisions respect the signed-in user's identity and permissions
- **Transparent controls**: Real-time badges show whether Purview allowed or blocked each interaction
- **Audit trail**: Every interaction is logged for compliance and forensics

## Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐    ┌──────────────────┐
│  Browser     │───▶│ Microsoft    │───▶│ AWS Lambda      │───▶│ Amazon Bedrock   │
│  (MSAL Auth) │    │ Entra ID     │    │ (Python 3.12)   │    │ (Nova 2 Lite)    │
└─────────────┘    │ OBO Exchange │    └─────────────────┘    └────────┬─────────┘
                   └──────────────┘           ▲   │                    │
                                              │   ▼                    ▼
                                    ┌──────────────────────┐  ┌──────────────────────┐
                                    │ Microsoft Purview    │  │ Gate 2: Model layer  │
                                    │                      │  │ control (Amazon      │
                                    │ Gate 1: Prompt DLP   │  │ Bedrock invocation,  │
                                    │ Gate 3: Response DLP │  │ guardrails, model    │
                                    └──────────────────────┘  │ access policy)       │
                                                              └──────────────────────┘
```

### Request flow

1. User authenticates with Microsoft Entra ID via MSAL.
2. Frontend sends the user's access token and prompt to the Lambda API.
3. Lambda exchanges the token using the OBO flow to create a Purview-scoped credential.
4. **Gate 1**: Purview DLP evaluates the prompt for sensitive information types (SITs).
5. If allowed, Lambda invokes Amazon Bedrock.
6. **Gate 2** (model layer control): Amazon Bedrock applies its own model-side controls — IAM access on `bedrock:InvokeModel`, the configured inference profile, and any Bedrock Guardrails attached to the model — before generating a response.
7. **Gate 3**: Purview DLP evaluates the response for sensitive information types.
8. If allowed, the response is returned with Purview evaluation metadata.
9. Frontend displays the result along with a green (allowed) or red (blocked) badge.

## Prerequisites

Before you begin, ensure you have:

- **AWS Account** with permissions to:
  - Create Lambda functions
  - Create API Gateway resources
  - Access Amazon Bedrock in `us-east-1`
  - Create and read from AWS Secrets Manager
  - Assume IAM roles

- **Microsoft Entra ID Tenant** with:
  - Permission to register applications
  - A tenant ID and domain (e.g., `yourdomain.onmicrosoft.com`)

- **Microsoft Purview Environment** with:
  - DLP policies available
  - Access to create and manage DLP rules

- **Local Development Environment**:
  - Python 3.9+
  - AWS CLI configured with credentials
  - Git

## Quick start

### 1. Clone the repository

```bash
git clone <repo-url>
cd BedrockExpenseAgent
```

### 2. Register a Microsoft Entra application

Create a new app registration in your Entra ID tenant:

1. Navigate to **Azure Portal** → **Entra ID** → **App registrations** → **New registration**
2. Name: `BedrockExpenseAgent` (or your preferred name)
3. Supported account types: Accounts in this organizational directory only
4. Redirect URI: `http://localhost:8080`
5. Click **Register**

After registration, note your:
- **Application (client) ID**
- **Directory (tenant) ID**

### 3. Create a client secret

1. In your app registration, go to **Certificates & secrets**
2. Click **New client secret**
3. Description: `Lambda OBO credentials`
4. Expiration: Choose 24 months or as per your policy
5. Copy the **Value** (you'll need it in step 5)

### 4. Expose an API scope

1. In your app registration, go to **Expose an API**
2. Click **Add a scope** next to the Application ID URI
3. Accept the default URI or customize it (e.g., `api://<client-id>`)
4. Add a scope with ID `access_as_user`
5. Grant admin consent

### 5. Store the Entra secret in AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name bedrock-agent/sharepoint-credentials \
  --secret-string '{"CLIENT_SECRET":"<your-client-secret>"}' \
  --region us-east-1
```

Note the **Secret ARN** for step 7.

### 6. Create or identify a DLP policy in Purview

Create a DLP policy that blocks sensitive information types such as:
- Credit Card Number
- Social Security Number
- Financial Account Data

You can optionally add exceptions for specific groups (e.g., Finance, HR).

### 7. Deploy AWS infrastructure

Update the CloudFormation parameters and deploy:

```bash
aws cloudformation deploy \
  --template-file cloudformation.yaml \
  --stack-name BedrockExpenseAgent \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    LambdaCodeBucket=<your-deployment-bucket> \
    BedrockModelId=us.amazon.nova-2-lite-v1:0 \
    SecretArn=arn:aws:secretsmanager:us-east-1:<account-id>:secret:bedrock-agent/sharepoint-credentials-xxxxx \
    TenantId=<your-tenant-id> \
    ClientId=<your-client-id> \
  --region us-east-1
```

After deployment, capture the **API endpoint** from CloudFormation outputs.

### 8. Update the frontend configuration

Edit `frontend/index.html` and update:

```javascript
const API_ENDPOINT = "https://<your-api-id>.execute-api.us-east-1.amazonaws.com/demo/agent/chat";

const msalConfig = {
    auth: {
        clientId: "<your-client-id>",
        authority: "https://login.microsoftonline.com/<your-tenant-id>",
        redirectUri: "http://localhost:8080",
    },
};
```

### 9. Run the frontend locally

```bash
cd frontend
python serve.py
```

Then open: `http://localhost:8080`

### 10. Test a safe prompt

1. Sign in with your Microsoft account
2. Ask a safe question like:
   ```
   What is the purpose of this application?
   ```
3. Verify the response is returned with a green Purview badge (`ALLOWED`)

### 11. Test a blocked prompt

1. Try a prompt containing sensitive information:
   ```
   Show me credit card number 4532-1234-5678-9010
   ```
2. Verify Purview blocks the prompt with a red badge (`BLOCKED`)

## Project structure

```
.
├── lambda/
│   ├── lambda_function.py                          # Main Lambda handler
│   └── requirements.txt                            # Python dependencies
├── frontend/
│   ├── index.html                                  # Single-page chat UI
│   └── serve.py                                    # Local HTTP server
├── cloudformation.yaml                             # AWS infrastructure template
├── create_purview_dlp_policy_customer_sample.ps1   # Sample Purview DLP policy
├── .env.example                                    # Local config template
└── README.md                                       # This file
```

## Key components

### Lambda function (`lambda/lambda_function.py`)

- Receives the user's MSAL access token and prompt
- Exchanges the token for a Purview-scoped credential via OBO
- Invokes Purview DLP middleware to evaluate prompts and responses
- Calls Amazon Bedrock with allowed prompts
- Returns results with Purview evaluation metadata

**Dependencies:**
- `agent-framework-core` — Message and framework types
- `agent-framework-purview` — Purview DLP middleware
- `azure-identity` — OBO credential flow
- `boto3` — AWS SDK

### Frontend (`frontend/index.html`)

- Uses MSAL.js for Entra ID authentication
- Single-page chat interface with message history
- Real-time Purview evaluation badges
- Responsive design with accessibility support

### CloudFormation template (`cloudformation.yaml`)

- Defines Lambda execution role with necessary permissions
- Creates Lambda function with environment variables
- Sets up API Gateway with CORS support
- Outputs the API endpoint for frontend configuration

## Configuration

### Environment variables (Lambda)

| Variable | Default | Purpose |
|----------|---------|---------|
| `AWS_REGION` | `us-east-1` | AWS region for Bedrock and other services |
| `BEDROCK_MODEL_ID` | `us.amazon.nova-2-lite-v1:0` | Bedrock model ID (use inference profile) |
| `TENANT_ID` | — | Microsoft Entra tenant ID |
| `CLIENT_ID` | — | Entra application (client) ID |

### Frontend configuration

Update `frontend/index.html`:

- `API_ENDPOINT` — Your API Gateway endpoint
- `clientId` — Your Entra application ID
- `authority` — Your Entra authority (tenant) URL
- `redirectUri` — Must match registered redirect URI

## Testing

### Unit tests

To add unit tests, create a `tests/` directory and use `pytest`:

```bash
cd lambda
pip install pytest
pytest tests/
```

### Integration testing

1. Deploy the full stack (Lambda + API Gateway)
2. Configure the frontend with your API endpoint
3. Sign in and test both allowed and blocked prompts
4. Verify Purview evaluation metadata in responses

### Troubleshooting

**Issue: "Authentication required. Please sign in with your Microsoft account."**
- Verify the `API_ENDPOINT` in the frontend matches your CloudFormation output
- Check that your Entra app registration allows `http://localhost:8080` as a redirect URI
- Ensure the MSAL configuration matches your Entra tenant and client ID

**Issue: Purview DLP errors or timeouts**
- Verify the Lambda execution role has permission to read the Secrets Manager secret
- Check that `ignore_exceptions=False` in `PurviewSettings` (fail-closed design)
- Review CloudWatch logs for the Lambda function: `aws logs tail /aws/lambda/BedrockExpenseAgent --follow`

**Issue: Bedrock model not found**
- Confirm the `BEDROCK_MODEL_ID` uses the inference profile (e.g., `us.amazon.nova-2-lite-v1:0`)
- Verify your AWS account has access to Amazon Bedrock in `us-east-1`

## Security considerations

- **No sensitive data in logs**: The Lambda avoids logging full prompts or responses
- **User identity in policy**: All DLP decisions are made under the signed-in user's identity
- **Secrets stored securely**: Entra secrets are stored in AWS Secrets Manager, not in code
- **API Gateway CORS**: Configured for `*` (should be restricted in production)

## License

This project is licensed under the MIT License — see the LICENSE file for details.

## Acknowledgments

This solution uses:
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [Microsoft Purview](https://learn.microsoft.com/en-us/purview/purview)
- [Amazon Bedrock](https://aws.amazon.com/bedrock/)
- [MSAL.js](https://github.com/AzureAD/microsoft-authentication-library-for-js)

## Disclaimer

This is a demonstration and educational project. Use at your own risk. Ensure you:
- Follow your organization's security and compliance policies
- Test thoroughly in a non-production environment before using with real data
- Monitor costs associated with AWS Lambda, API Gateway, and Amazon Bedrock
- Keep dependencies and secrets up to date
