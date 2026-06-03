"""
BedrockExpenseAgent — Lambda handler with Purview inline DLP.

Architecture:
  MSAL frontend → API Gateway → this Lambda → Bedrock (Nova 2 Lite)
  PurviewPolicyMiddleware evaluates every prompt and response for sensitive
  information types (credit cards, SSNs, etc.) using the delegated user identity.

Flow:
  1. User authenticates via MSAL (Entra ID) in the browser
  2. Frontend passes the user's access token + prompt to API Gateway
  3. Purview evaluates the prompt for sensitive info types (UPLOAD_TEXT)
  4. Lambda calls Bedrock with the prompt
  5. Purview evaluates the response for sensitive info types (DOWNLOAD_TEXT)
  6. If sensitive data is detected, Purview blocks it inline
"""

import asyncio
import json
import logging
import os

import boto3
from azure.identity import OnBehalfOfCredential
from agent_framework import Message
from agent_framework.microsoft import PurviewPolicyMiddleware, PurviewSettings
from agent_framework_purview._models import Activity

logger = logging.getLogger(__name__)

# ── Config ──────────────────────────────────────────────────────────
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.amazon.nova-2-lite-v1:0")

TENANT_ID = os.environ.get("TENANT_ID", "")
CLIENT_ID = os.environ.get("CLIENT_ID", "")

bedrock_client = boto3.client("bedrock-runtime", region_name=AWS_REGION)
secrets_client = boto3.client("secretsmanager", region_name=AWS_REGION)

_cached_secret = None


def get_client_secret():
    """Retrieve the Entra client secret from Secrets Manager."""
    global _cached_secret
    if _cached_secret:
        return _cached_secret
    secret = secrets_client.get_secret_value(
        SecretId="bedrock-agent/sharepoint-credentials"
    )
    data = json.loads(secret["SecretString"])
    _cached_secret = data["CLIENT_SECRET"]
    return _cached_secret


def call_bedrock(prompt: str) -> str:
    """Call Bedrock Nova 2 Lite with the given prompt."""
    body = json.dumps({
        "messages": [{"role": "user", "content": [{"text": prompt}]}],
        "inferenceConfig": {
            "maxTokens": 2048,
            "temperature": 0.3,
        },
    })
    response = bedrock_client.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=body,
    )
    result = json.loads(response["body"].read())
    return result["output"]["message"]["content"][0]["text"]


def get_purview_credential(user_token: str):
    """Create an OBO credential for Purview SDK using the user's access token."""
    return OnBehalfOfCredential(
        tenant_id=TENANT_ID,
        client_id=CLIENT_ID,
        client_secret=get_client_secret(),
        user_assertion=user_token,
    )


async def run_with_purview(user_token: str, user_prompt: str) -> dict:
    """
    Run the agent pipeline with Purview inline DLP:
    1. Purview evaluates the user prompt for sensitive info types (UPLOAD_TEXT)
    2. Call Bedrock with the prompt
    3. Purview evaluates the response for sensitive info types (DOWNLOAD_TEXT)
    4. Return result or Purview block message
    """
    system_prompt = (
        "You are the Contoso Corp Expense Approval Agent.\n"
        "Answer questions about expenses, reimbursements, employee expense records, "
        "salary information, and company HR policies.\n"
        "Do NOT fabricate employee data, expense amounts, or policy details.\n"
    )

    full_prompt = f"{system_prompt}\n\nUser: {user_prompt}"

    # Create Purview middleware with the user's delegated identity
    purview_credential = get_purview_credential(user_token)
    purview_settings = PurviewSettings(
        app_name="ExpenseApprovalAgent-Bedrock",
        blocked_prompt_message=(
            "Your request was blocked by a Microsoft Purview DLP policy. "
            "The prompt contains content that violates organizational data protection rules."
        ),
        blocked_response_message=(
            "This response was blocked by a Microsoft Purview DLP policy. "
            "The content contains sensitive data that cannot be disclosed."
        ),
        ignore_exceptions=False,
    )
    purview_mw = PurviewPolicyMiddleware(
        credential=purview_credential,
        settings=purview_settings,
    )

    # Metadata tracking for Purview evaluation transparency
    purview_meta = {
        "promptEvaluated": False,
        "promptVerdict": None,
        "responseEvaluated": False,
        "responseVerdict": None,
    }

    try:
        # Gate 1: Check prompt against Purview DLP (UPLOAD_TEXT)
        prompt_messages = [Message(role="user", contents=[full_prompt])]
        should_block_prompt, user_id = await purview_mw._processor.process_messages(
            prompt_messages, Activity.UPLOAD_TEXT
        )
        purview_meta["promptEvaluated"] = True
        purview_meta["promptVerdict"] = "BLOCKED" if should_block_prompt else "ALLOWED"
        if should_block_prompt:
            return {
                "blocked": True,
                "blockReason": "PURVIEW_DLP_PROMPT",
                "message": purview_settings.get("blocked_prompt_message",
                    "Prompt blocked by Purview DLP policy."),
                "purview": purview_meta,
            }

        # Gate 2: Call Bedrock
        agent_response = call_bedrock(full_prompt)

        # Gate 3: Check response against Purview DLP (DOWNLOAD_TEXT)
        response_messages = [Message(role="assistant", contents=[agent_response])]
        should_block_response, _ = await purview_mw._processor.process_messages(
            response_messages, Activity.DOWNLOAD_TEXT, user_id=user_id
        )
        purview_meta["responseEvaluated"] = True
        purview_meta["responseVerdict"] = "BLOCKED" if should_block_response else "ALLOWED"
        if should_block_response:
            return {
                "blocked": True,
                "blockReason": "PURVIEW_DLP_RESPONSE",
                "message": purview_settings.get("blocked_response_message",
                    "Response blocked by Purview DLP policy."),
                "purview": purview_meta,
            }

        return {
            "blocked": False,
            "message": agent_response,
            "purview": purview_meta,
        }

    except Exception as e:
        error_msg = str(e)
        # Only catch genuine Purview errors, not AWS IAM/policy errors
        if "purview" in error_msg.lower():
            return {
                "blocked": True,
                "blockReason": "PURVIEW_DLP",
                "message": f"Blocked by Purview DLP policy: {error_msg}",
                "purview": purview_meta,
            }
        raise


def lambda_handler(event, context):
    """API Gateway Lambda proxy handler."""
    try:
        # Handle CORS preflight
        if event.get("httpMethod") == "OPTIONS":
            return {"statusCode": 200, "headers": _cors_headers(), "body": ""}

        # Parse request
        if isinstance(event.get("body"), str):
            body = json.loads(event["body"])
        else:
            body = event.get("body") or event

        user_token = body.get("userAccessToken")
        user_prompt = body.get("prompt", body.get("inputText", ""))

        if not user_token:
            return {
                "statusCode": 401,
                "headers": _cors_headers(),
                "body": json.dumps({
                    "message": "Authentication required. Please sign in with your Microsoft account.",
                    "blockReason": "NO_TOKEN",
                }),
            }

        if not user_prompt:
            return {
                "statusCode": 400,
                "headers": _cors_headers(),
                "body": json.dumps({"message": "No prompt provided."}),
            }

        # Run the agent with Purview middleware
        result = asyncio.get_event_loop().run_until_complete(
            run_with_purview(user_token, user_prompt)
        )

        if result.get("blocked"):
            return {
                "statusCode": 403,
                "headers": _cors_headers(),
                "body": json.dumps(result),
            }

        return {
            "statusCode": 200,
            "headers": _cors_headers(),
            "body": json.dumps(result),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": _cors_headers(),
            "body": json.dumps({"message": f"Internal error: {str(e)}"}),
        }


def _cors_headers():
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Allow-Methods": "POST,OPTIONS",
    }
