"""Explicit Temporal connection settings, shared by workers and namespace tooling."""

import os
from pathlib import Path

from pydantic_ai.durable_exec.temporal import PydanticAIPlugin
from temporalio.client import Client
from temporalio.service import TLSConfig


def settings() -> dict:
    namespace = os.environ.get("STARBASE_TEMPORAL_NAMESPACE", "default")
    production = os.environ.get("STARBASE_ENV") == "production"
    if production and namespace == "default":
        raise ValueError("Production requires a dedicated Temporal namespace")
    cert = os.environ.get("STARBASE_TEMPORAL_CERT_FILE")
    key = os.environ.get("STARBASE_TEMPORAL_KEY_FILE")
    ca = os.environ.get("STARBASE_TEMPORAL_CA_FILE")
    if bool(cert) != bool(key):
        raise ValueError("Temporal client certificate and key must be configured together")
    tls: bool | TLSConfig = False
    if cert or ca or os.environ.get("STARBASE_TEMPORAL_TLS") == "true":
        tls = TLSConfig(
            client_cert=Path(cert).read_bytes() if cert else None,
            client_private_key=Path(key).read_bytes() if key else None,
            server_root_ca_cert=Path(ca).read_bytes() if ca else None,
            domain=os.environ.get("STARBASE_TEMPORAL_SERVER_NAME"),
        )
    return {
        "target_host": os.environ.get("STARBASE_TEMPORAL", "127.0.0.1:7233"),
        "namespace": namespace,
        "tls": tls,
        "plugins": [PydanticAIPlugin()],
    }


async def connect() -> Client:
    return await Client.connect(**settings())
