# Copyright (c) Microsoft. All rights reserved.
"""Generic Agent Host — hosts an agent implementing AgentInterface behind the real
Bot Framework layer so Microsoft Teams / Copilot and A365 notifications reach it.

Structure follows the verified Agent365-Samples/python/agent-framework/sample-agent
host, with one deployment change: the server binds 0.0.0.0 (not localhost) so Azure
Container Apps ingress can route to it.

The HOST owns observability: it exchanges the per-turn Observability-API token
(`_setup_observability_token`) and wraps each turn in a BaggageBuilder scope, so the
agent code stays focused on the LLM. Inference / tool spans come from the distro's
auto-instrumentation of Agent Framework.
"""

import asyncio
import logging
import os
import socket
from os import environ

from aiohttp.web import Application, Request, Response, json_response, run_app
from aiohttp.web_middlewares import middleware as web_middleware
from dotenv import load_dotenv

from agent_interface import AgentInterface, check_agent_inheritance
from microsoft_agents.activity import load_configuration_from_env, Activity
from microsoft_agents.authentication.msal import MsalConnectionManager
from microsoft_agents.hosting.aiohttp import (
    CloudAdapter,
    jwt_authorization_middleware,
    start_agent_process,
)
from microsoft_agents.hosting.core import (
    AgentApplication,
    AgentAuthConfiguration,
    AuthenticationConstants,
    Authorization,
    ClaimsIdentity,
    MemoryStorage,
    TurnContext,
    TurnState,
)
from microsoft_agents_a365.notifications.agent_notification import (
    AgentNotification,
    NotificationTypes,
    AgentNotificationActivity,
    ChannelId,
)
from microsoft_agents_a365.notifications import EmailResponse

from microsoft.opentelemetry import use_microsoft_opentelemetry
from microsoft_agents_a365.observability.core.middleware.baggage_builder import (
    BaggageBuilder,
)
from microsoft_agents_a365.runtime.environment_utils import (
    get_observability_authentication_scope,
)
from token_cache import cache_agentic_token, get_cached_agentic_token

# --- Configuration ---
ms_agents_logger = logging.getLogger("microsoft_agents")
ms_agents_logger.addHandler(logging.StreamHandler())
ms_agents_logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

logging.getLogger("microsoft_agents_a365.observability").setLevel(logging.ERROR)
logger = logging.getLogger(__name__)

# Load THIS project's own .env (a365-agent-full/.env, the parent of backend/) by an EXPLICIT
# absolute path — never depends on the working directory, never picks up another project's .env.
# (In the container there is no .env; config comes from Container Apps env vars — load_dotenv on a
# missing file is a harmless no-op.)
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))
agents_sdk_config = load_configuration_from_env(environ)


def create_and_run_host(agent_class: type[AgentInterface], *agent_args, **agent_kwargs):
    """Create and run a generic agent host."""
    if not check_agent_inheritance(agent_class):
        raise TypeError(f"Agent class {agent_class.__name__} must inherit from AgentInterface")

    # Initialize the Microsoft OpenTelemetry distro (A365 exporter). The exporter's
    # auth token is minted per-turn by the host and read back through this resolver.
    use_microsoft_opentelemetry(
        enable_a365=True,
        enable_azure_monitor=False,
        a365_enable_observability_exporter=os.getenv(
            "ENABLE_A365_OBSERVABILITY_EXPORTER", "false"
        ).strip().lower()
        == "true",
        a365_token_resolver=lambda agent_id, tenant_id: get_cached_agentic_token(tenant_id, agent_id)
        or "",
    )

    host = GenericAgentHost(agent_class, *agent_args, **agent_kwargs)
    auth_config = host.create_auth_configuration()
    host.start_server(auth_config)


class GenericAgentHost:
    """Generic host for agents implementing AgentInterface."""

    def __init__(self, agent_class: type[AgentInterface], *agent_args, **agent_kwargs):
        if not check_agent_inheritance(agent_class):
            raise TypeError(f"Agent class {agent_class.__name__} must inherit from AgentInterface")

        # AUTH_HANDLER_NAME=AGENTIC in prod; empty for anonymous local dev.
        self.auth_handler_name = os.getenv("AUTH_HANDLER_NAME", "") or None
        logger.info(
            "🔐 Using auth handler: %s" if self.auth_handler_name else "🔓 No auth handler configured",
            self.auth_handler_name or "",
        )

        self.agent_class = agent_class
        self.agent_args = agent_args
        self.agent_kwargs = agent_kwargs
        self.agent_instance: AgentInterface | None = None

        self.storage = MemoryStorage()
        self.connection_manager = MsalConnectionManager(**agents_sdk_config)
        self.adapter = CloudAdapter(connection_manager=self.connection_manager)
        self.authorization = Authorization(self.storage, self.connection_manager, **agents_sdk_config)
        self.agent_app = AgentApplication[TurnState](
            storage=self.storage,
            adapter=self.adapter,
            authorization=self.authorization,
            **agents_sdk_config,
        )
        self.agent_notification = AgentNotification(self.agent_app)
        self._setup_handlers()
        logger.info("✅ Handlers registered")

    # --- Observability (host-owned) ---
    async def _setup_observability_token(self, context: TurnContext, tenant_id: str, agent_id: str):
        if not self.auth_handler_name:
            return
        try:
            exaau_token = await self.agent_app.auth.exchange_token(
                context,
                scopes=get_observability_authentication_scope(),
                auth_handler_id=self.auth_handler_name,
            )
            cache_agentic_token(tenant_id, agent_id, exaau_token.token)
        except Exception as e:
            logger.warning("⚠️ Failed to cache observability token: %s", e)

    async def _validate_agent_and_setup_context(self, context: TurnContext):
        tenant_id = context.activity.recipient.tenant_id
        agent_id = context.activity.recipient.agentic_app_id
        if not self.agent_instance:
            await context.send_activity("❌ Sorry, the agent is not available.")
            return None
        await self._setup_observability_token(context, tenant_id, agent_id)
        return tenant_id, agent_id

    # --- Handlers ---
    def _setup_handlers(self):
        handler_config = {"auth_handlers": [self.auth_handler_name]} if self.auth_handler_name else {}

        async def help_handler(context: TurnContext, _: TurnState):
            await context.send_activity(
                f"👋 Hi! I'm your Microsoft 365 AI teammate. How can I help you today?"
            )

        self.agent_app.conversation_update("membersAdded", **handler_config)(help_handler)
        self.agent_app.message("/help", **handler_config)(help_handler)

        @self.agent_app.activity("installationUpdate")
        async def on_installation_update(context: TurnContext, _: TurnState):
            action = context.activity.action
            if action == "add":
                await context.send_activity("Thanks for hiring me — looking forward to working with you!")
            elif action == "remove":
                await context.send_activity("Thanks for your time — I enjoyed working with you.")

        @self.agent_app.activity("message", **handler_config)
        async def on_message(context: TurnContext, _: TurnState):
            try:
                result = await self._validate_agent_and_setup_context(context)
                if result is None:
                    return
                tenant_id, agent_id = result

                with BaggageBuilder().tenant_id(tenant_id).agent_id(agent_id).build():
                    user_message = context.activity.text or ""
                    if not user_message.strip() or user_message.strip() == "/help":
                        return

                    await context.send_activity("Got it — working on it…")
                    await context.send_activity(Activity(type="typing"))

                    async def _typing_loop():
                        try:
                            while True:
                                await asyncio.sleep(4)
                                await context.send_activity(Activity(type="typing"))
                        except asyncio.CancelledError:
                            pass

                    typing_task = asyncio.create_task(_typing_loop())
                    try:
                        response = await self.agent_instance.process_user_message(
                            user_message, self.agent_app.auth, self.auth_handler_name, context
                        )
                        await context.send_activity(response)
                    finally:
                        typing_task.cancel()
                        try:
                            await typing_task
                        except asyncio.CancelledError:
                            pass
            except Exception as e:
                logger.error("❌ Error: %s", e)
                await context.send_activity(f"Sorry, I encountered an error: {e}")

        @self.agent_notification.on_agent_notification(
            channel_id=ChannelId(channel="agents", sub_channel="*"),
            **handler_config,
        )
        async def on_notification(
            context: TurnContext,
            state: TurnState,
            notification_activity: AgentNotificationActivity,
        ):
            try:
                result = await self._validate_agent_and_setup_context(context)
                if result is None:
                    return
                tenant_id, agent_id = result

                with BaggageBuilder().tenant_id(tenant_id).agent_id(agent_id).build():
                    if not hasattr(self.agent_instance, "handle_agent_notification_activity"):
                        await context.send_activity("This agent doesn't support notifications yet.")
                        return

                    response = await self.agent_instance.handle_agent_notification_activity(
                        notification_activity, self.agent_app.auth, self.auth_handler_name, context
                    )

                    if notification_activity.notification_type == NotificationTypes.EMAIL_NOTIFICATION:
                        await context.send_activity(
                            EmailResponse.create_email_response_activity(response)
                        )
                        return
                    if response:
                        await context.send_activity(response)
            except Exception as e:
                logger.error("❌ Notification error: %s", e)
                await context.send_activity(f"Sorry, I hit an error handling that notification: {e}")

    # --- Agent lifecycle ---
    async def initialize_agent(self):
        if self.agent_instance is None:
            logger.info("🤖 Initializing %s…", self.agent_class.__name__)
            self.agent_instance = self.agent_class(*self.agent_args, **self.agent_kwargs)
            await self.agent_instance.initialize()

    def create_auth_configuration(self) -> AgentAuthConfiguration | None:
        client_id = environ.get("CLIENT_ID")
        tenant_id = environ.get("TENANT_ID")
        client_secret = environ.get("CLIENT_SECRET")
        if client_id and tenant_id and client_secret:
            logger.info("🔒 Using Client Credentials authentication")
            return AgentAuthConfiguration(
                client_id=client_id,
                tenant_id=tenant_id,
                client_secret=client_secret,
                scopes=["5a807f24-c9de-44ee-a3a7-329e88a00ffc/.default"],
            )
        logger.warning("⚠️ No CLIENT_ID/TENANT_ID/CLIENT_SECRET — running anonymous (local dev)")
        return None

    # --- Server ---
    def start_server(self, auth_configuration: AgentAuthConfiguration | None = None):
        async def entry_point(req: Request) -> Response:
            return await start_agent_process(req, req.app["agent_app"], req.app["adapter"])

        async def health(_req: Request) -> Response:
            return json_response(
                {
                    "status": "ok",
                    "agent_type": self.agent_class.__name__,
                    "agent_initialized": self.agent_instance is not None,
                }
            )

        middlewares = []
        if auth_configuration:

            @web_middleware
            async def jwt_with_health_bypass(request, handler):
                # Health must be reachable without a bearer token (Container Apps probe).
                if request.path == "/api/health":
                    return await handler(request)
                return await jwt_authorization_middleware(request, handler)

            middlewares.append(jwt_with_health_bypass)

        @web_middleware
        async def anonymous_claims(request, handler):
            if not auth_configuration:
                request["claims_identity"] = ClaimsIdentity(
                    {
                        AuthenticationConstants.AUDIENCE_CLAIM: "anonymous",
                        AuthenticationConstants.APP_ID_CLAIM: "anonymous-app",
                    },
                    False,
                    "Anonymous",
                )
            return await handler(request)

        middlewares.append(anonymous_claims)
        app = Application(middlewares=middlewares)
        app.router.add_post("/api/messages", entry_point)
        app.router.add_get("/api/messages", lambda _: Response(status=200))
        app.router.add_get("/api/health", health)
        app["agent_configuration"] = auth_configuration
        app["agent_app"] = self.agent_app
        app["adapter"] = self.agent_app.adapter
        app.on_startup.append(lambda app: self.initialize_agent())
        app.on_shutdown.append(lambda app: self.cleanup())

        # Bind 0.0.0.0 so Azure Container Apps ingress (and any container host) can route in.
        host_bind = os.getenv("HOST", "0.0.0.0")
        port = int(environ.get("PORT", 3978))

        print("=" * 72)
        print(f"🏢 {self.agent_class.__name__}")
        print(f"🔒 Auth: {'Enabled' if auth_configuration else 'Anonymous (local dev)'}")
        print(f"🚀 Listening on http://{host_bind}:{port}/api/messages  (health: /api/health)")
        print("=" * 72)

        try:
            run_app(app, host=host_bind, port=port, handle_signals=True)
        except KeyboardInterrupt:
            print("\n👋 Server stopped")

    async def cleanup(self):
        if self.agent_instance:
            try:
                await self.agent_instance.cleanup()
            except Exception as e:
                logger.error("Cleanup error: %s", e)
