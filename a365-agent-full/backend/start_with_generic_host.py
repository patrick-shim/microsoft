#!/usr/bin/env python3
# Copyright (c) Microsoft. All rights reserved.
"""Entry point — start the generic host with MyAgent (the AI Teammate)."""

import sys


def main() -> int:
    try:
        from agent_full import MyAgent
        from host_agent_server import create_and_run_host
    except ImportError as e:
        print(f"Import error: {e}\nRun from the backend/ directory.")
        return 1

    try:
        print("Starting Agent 365 AI Teammate host…\n")
        create_and_run_host(MyAgent)
    except Exception as e:  # pragma: no cover
        import traceback

        print(f"❌ Failed to start server: {e}")
        traceback.print_exc()
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
