# Copyright (c) Microsoft. All rights reserved.
"""In-process token cache for the Agent 365 Observability exporter.

The host exchanges an observability token per turn (`cache_agentic_token`); the
OTel exporter reads it back via `get_cached_agentic_token` through the resolver
wired in `create_and_run_host`. Verbatim from the verified AF sample.
"""

import logging

logger = logging.getLogger(__name__)

_agentic_token_cache: dict[str, str] = {}


def cache_agentic_token(tenant_id: str, agent_id: str, token: str) -> None:
    """Cache the agentic token for the Agent 365 Observability exporter."""
    key = f"{tenant_id}:{agent_id}"
    _agentic_token_cache[key] = token
    logger.debug("Cached agentic token for %s", key)


def get_cached_agentic_token(tenant_id: str, agent_id: str) -> str | None:
    """Retrieve the cached agentic token for the Agent 365 Observability exporter."""
    key = f"{tenant_id}:{agent_id}"
    token = _agentic_token_cache.get(key)
    logger.debug("%s cached token for %s", "Retrieved" if token else "No", key)
    return token
