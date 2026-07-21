# Copyright (c) Microsoft. All rights reserved.
# Container image for the Agent 365 AI Teammate host.
# Build context is this backend/ directory:  docker build -t a365-full-demo backend/
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=3978 \
    PYTHON_ENVIRONMENT=Production

# uv — fast, reproducible installs (copied from the official distroless image).
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Copy the app (pyproject + sources + ToolingManifest.json) and resolve dependencies.
# ToolingManifest.json must be present so the WorkIQ SDK can discover MCP servers at runtime.
COPY . /app
RUN uv sync --no-dev

# Run as a non-root user.
RUN useradd --create-home --uid 10001 appuser && chown -R appuser /app
USER appuser

EXPOSE 3978

# Liveness probe hits the unauthenticated /api/health route.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,os,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:'+os.getenv('PORT','3978')+'/api/health').status==200 else 1)"

CMD ["uv", "run", "python", "start_with_generic_host.py"]
