# Copyright (c) Microsoft. All rights reserved.
"""Agent base class — the contract the generic host requires (verbatim from the
verified Agent365-Samples/python/agent-framework/sample-agent)."""

from abc import ABC, abstractmethod
from typing import Optional

from microsoft_agents.hosting.core import Authorization, TurnContext


class AgentInterface(ABC):
    """Abstract base class that any hosted agent must inherit from.

    Ensures agents implement the required methods at class-definition time,
    giving stronger guarantees than a Protocol.
    """

    @abstractmethod
    async def initialize(self) -> None:
        """Initialize the agent and any required resources."""

    @abstractmethod
    async def process_user_message(
        self,
        message: str,
        auth: Authorization,
        auth_handler_name: Optional[str],
        context: TurnContext,
    ) -> str:
        """Process a user message and return a response."""

    @abstractmethod
    async def cleanup(self) -> None:
        """Clean up any resources used by the agent."""


def check_agent_inheritance(agent_class) -> bool:
    """Return True iff agent_class inherits from AgentInterface."""
    if not issubclass(agent_class, AgentInterface):
        print(f"❌ Agent {agent_class.__name__} does not inherit from AgentInterface")
        return False
    return True
