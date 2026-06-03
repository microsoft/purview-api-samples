# TODO: boto3 wrapper around bedrock-runtime InvokeModel for Amazon Nova 2 Lite.
#
# Suggested implementation:
#
#   import boto3, json, os
#
#   _client = boto3.client(
#       "bedrock-runtime",
#       region_name=os.environ.get("AWS_REGION", "us-east-1"),
#   )
#
#   MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-lite-v2:0")
#
#   def invoke_nova_lite(prompt: str) -> str:
#       """Call Amazon Bedrock Nova 2 Lite and return the response text."""
#       body = json.dumps({
#           "messages": [
#               {"role": "user", "content": [{"text": prompt}]},
#           ],
#           "inferenceConfig": {"maxTokens": 1024, "temperature": 0.2},
#       })
#       resp = _client.invoke_model(modelId=MODEL_ID, body=body)
#       payload = json.loads(resp["body"].read())
#       return payload["output"]["message"]["content"][0]["text"]
