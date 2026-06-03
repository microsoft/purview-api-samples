# TODO: Lambda entry point for the expense approval agent.
#
# Recommended shape (drop your real implementation here):
#
#   import json, os, uuid
#   from purview_client import PurviewClient, exchange_obo_for_graph_token
#   from bedrock_client import invoke_nova_lite
#
#   def lambda_handler(event, context):
#       # 1. Extract user access token from Authorization header
#       auth = event["headers"].get("authorization", "")
#       user_token = auth.removeprefix("Bearer ").strip()
#       body = json.loads(event.get("body") or "{}")
#       prompt = body.get("prompt", "")
#       correlation_id = str(uuid.uuid4())
#
#       # 2. OBO exchange for a Microsoft Graph token
#       graph_token = exchange_obo_for_graph_token(user_token)
#       purview = PurviewClient(graph_token, app_client_id=os.environ["CLIENT_ID"])
#
#       # 3. Pre-flight: compute protection scopes (cacheable)
#       purview.compute_protection_scopes(user_id=body.get("userId", ""))
#
#       # 4. Inline DLP on the prompt
#       upload_verdict = purview.process_content(
#           text=prompt, activity="uploadText",
#           correlation_id=correlation_id, sequence_number=1,
#       )
#       if PurviewClient.is_blocked(upload_verdict):
#           return _resp(403, {
#               "blocked": True, "stage": "prompt",
#               "purview": upload_verdict,
#           })
#
#       # 5. Call Amazon Bedrock (Nova 2 Lite)
#       answer = invoke_nova_lite(prompt)
#
#       # 6. Inline DLP on the response
#       download_verdict = purview.process_content(
#           text=answer, activity="downloadText",
#           correlation_id=correlation_id, sequence_number=2,
#       )
#       if PurviewClient.is_blocked(download_verdict):
#           return _resp(403, {
#               "blocked": True, "stage": "response",
#               "purview": download_verdict,
#           })
#
#       # 7. Return answer + governance verdict to the SPA
#       return _resp(200, {
#           "blocked": False,
#           "answer": answer,
#           "purview": {"prompt": upload_verdict, "response": download_verdict},
#       })
#
#   def _resp(status, payload):
#       return {
#           "statusCode": status,
#           "headers": {"Content-Type": "application/json"},
#           "body": json.dumps(payload),
#       }
