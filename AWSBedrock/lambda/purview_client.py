# TODO: Microsoft Graph wrapper for Purview protection-scopes + processContent.
#
# This module is intentionally generic and can be copied verbatim from the
# Foundry sample (Foundry/.../purview_client.py) — Purview's Graph surface
# does not change when the model runtime is AWS Bedrock instead of Azure
# OpenAI.
#
# Suggested public surface:
#
#   class PurviewClient:
#       def __init__(self, graph_token: str, app_client_id: str): ...
#       def compute_protection_scopes(self, user_id: str) -> dict: ...
#       def process_content(
#           self,
#           text: str,
#           activity: str,            # "uploadText" or "downloadText"
#           correlation_id: str,
#           sequence_number: int,
#       ) -> dict: ...
#       def log_content_activity(self, ...) -> None: ...
#
#       @staticmethod
#       def parse_execution_modes(scopes: dict) -> list[str]: ...
#       @staticmethod
#       def is_blocked(verdict: dict) -> bool: ...
#       @staticmethod
#       def extract_block_details(verdict: dict) -> dict: ...
#       @staticmethod
#       def mask_sensitive_text(text: str, spans: list) -> str: ...
#
#   def exchange_obo_for_graph_token(user_assertion: str) -> str:
#       """OAuth 2.0 On-Behalf-Of: exchange the user's access token for a
#       Microsoft Graph token. Uses MSAL ConfidentialClientApplication."""
#       ...
