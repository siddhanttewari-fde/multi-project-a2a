"""Centralized configuration for Coordinator Agent A and Specialist Agent B."""

import os
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

AGENTS_ROOT_DIR = str(Path(__file__).resolve().parent.parent)
ADK_AGENT_EXECUTOR_EXTENSION_URI = (
    "https://google.github.io/adk-docs/a2a/a2a-extension/"
)
CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
A2A_HMAC_TIMESTAMP_HEADER = "X-A2A-Timestamp"
A2A_HMAC_NONCE_HEADER = "X-A2A-Nonce"
A2A_HMAC_SIGNATURE_HEADER = "X-A2A-Signature"


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = Field(default="app", alias="APP_NAME")
    app_version: str = Field(default="0.1.0", alias="AGENT_VERSION")
    host: str = Field(default="0.0.0.0", alias="HOST")
    port: int = Field(default=8080, alias="PORT")
    gemini_model: str = Field(default="gemini-3.5-flash", alias="GEMINI_MODEL")

    google_genai_use_vertexai: bool = Field(
        default=True,
        alias="GOOGLE_GENAI_USE_VERTEXAI",
    )
    google_cloud_project: str = Field(default="", alias="GOOGLE_CLOUD_PROJECT")
    google_cloud_location: str = Field(
        default="global",
        alias="GOOGLE_CLOUD_LOCATION",
    )
    google_cloud_agent_engine_id: str = Field(
        default="",
        alias="GOOGLE_CLOUD_AGENT_ENGINE_ID",
    )
    google_cloud_agent_engine_location: str = Field(
        default="us-central1",
        alias="GOOGLE_CLOUD_AGENT_ENGINE_LOCATION",
    )
    google_cloud_agent_engine_enable_telemetry: str = Field(
        default="true",
        alias="GOOGLE_CLOUD_AGENT_ENGINE_ENABLE_TELEMETRY",
    )
    google_api_use_client_certificate: str = Field(
        default="false",
        alias="GOOGLE_API_USE_CLIENT_CERTIFICATE",
    )
    google_api_use_mtls_endpoint: str = Field(
        default="never",
        alias="GOOGLE_API_USE_MTLS_ENDPOINT",
    )

    gateway_project_id: str = Field(default="", alias="GATEWAY_PROJECT_ID")
    region: str = Field(default="us-central1", alias="REGION")
    remote_agent_b_id: str = Field(
        default="agents/specialist-agent-b",
        alias="REMOTE_AGENT_B_ID",
    )

    app_url: str = Field(default="", alias="APP_URL")
    allow_origins_raw: str = Field(default="", alias="ALLOW_ORIGINS")
    a2a_rpc_path: str = Field(default="/a2a/app", alias="A2A_RPC_PATH")
    http_timeout_seconds: float = Field(default=60.0, alias="HTTP_TIMEOUT_SECONDS")
    a2a_hmac_secret: str = Field(default="", alias="A2A_HMAC_SECRET")
    a2a_hmac_ttl_seconds: int = Field(
        default=300,
        alias="A2A_HMAC_TTL_SECONDS",
    )


def _configure_tls_intercepted_env(cfg: Settings) -> Settings:
    """Disable client-cert mTLS URL rewriting when traversing Central Egress Gateway."""
    os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = (
        cfg.google_api_use_client_certificate
    )
    os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = cfg.google_api_use_mtls_endpoint
    return cfg


settings = _configure_tls_intercepted_env(Settings())
