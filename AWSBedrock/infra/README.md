# Infrastructure for the Bedrock + Purview expense approval agent

This sample is deliberately framework-neutral — pick the AWS deployment
tool your team already uses.

## Choose one

- **AWS SAM** — simplest path. `sam init`, point it at `../lambda/`, add
  an `AWS::Serverless::HttpApi` event for `/chat`.
- **AWS CDK** — best if you already have a CDK app. Use
  `aws-cdk-lib/aws-lambda` + `aws-apigatewayv2-alpha` HTTP API.
- **Terraform** — use `hashicorp/aws` provider with
  `aws_lambda_function` + `aws_apigatewayv2_api`.

Whichever you choose, the Lambda needs:

| Setting | Value |
| --- | --- |
| Runtime | `python3.12` (or later) |
| Handler | `handler.lambda_handler` |
| Timeout | 30 s |
| Memory | 512 MB |
| Layers / package | bundle `requirements.txt` |
| Env vars | from `.env.example` below |
| IAM | `bedrock:InvokeModel` + CloudWatch Logs |

API Gateway in front of the Lambda should expose a single `POST /chat`
route that requires the caller to send an `Authorization: Bearer <token>`
header containing an Entra ID access token whose audience is this app
registration's client ID.

## Configuration

Copy `.env.example` to `.env`, fill in the values, and inject them as the
Lambda's environment variables at deploy time. Do **not** commit `.env`.
