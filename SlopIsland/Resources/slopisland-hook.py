#!/usr/bin/env python3
# /// script
# requires-python = ">=3.14"
# ///
"""SlopIsland Hook - bridges Claude Code session state to SlopIsland.app.

Sends each hook event to SlopIsland.app over a private Unix-domain socket.
For PermissionRequest it blocks waiting for the user's Allow/Deny decision from
the app, then translates that into Claude Code's official hook output format.

This is the ONLY place that knows Claude Code's hook contract; the Swift app
only speaks the small private JSON protocol defined here. SlopIsland is fully
decoupled from any other tool (it does NOT reuse circleask's socket).
"""

from __future__ import annotations

import json
import os
import socket
import sys
from pathlib import Path

# Private socket under the app's Application Support dir (chmod 0700 by the app).
SOCKET_PATH = Path(
    os.path.expanduser("~/Library/Application Support/SlopIsland/hook.sock")
)
CONNECT_TIMEOUT_SECONDS = 5
# Must match HookServer.permissionTimeoutSeconds on the Swift side.
PERMISSION_RECV_TIMEOUT_SECONDS = 300

_DEBUG = os.environ.get("SLOPISLAND_DEBUG") == "1" or os.path.exists(
    os.path.expanduser("~/Library/Application Support/SlopIsland/.debug")
)
_LOG = os.path.expanduser("~/Library/Application Support/SlopIsland/hook.log")


def _log(msg: str) -> None:
    if not _DEBUG:
        return
    try:
        with open(_LOG, "a") as f:
            f.write(msg + "\n")
    except OSError:
        pass


def send_event(payload: dict) -> dict | None:
    """Send one event; return the app's response dict for permission requests."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(CONNECT_TIMEOUT_SECONDS)
            _log(f"connecting (status={payload.get('status')})")
            sock.connect(str(SOCKET_PATH))
            _log("connected; sending")
            sock.sendall(json.dumps(payload).encode())
            sock.shutdown(socket.SHUT_WR)  # signal end-of-request to the app
            _log("sent + shutdown(WR)")

            if payload.get("status") != "waiting_for_approval":
                return None

            # Block until the app writes a decision and closes the socket (EOF).
            sock.settimeout(PERMISSION_RECV_TIMEOUT_SECONDS)
            _log("waiting for decision (recv)...")
            chunks: list[bytes] = []
            while chunk := sock.recv(4096):
                chunks.append(chunk)
            raw = b"".join(chunks)
            _log(f"recv done: {raw!r}")
            if not raw:
                return None
            parsed = json.loads(raw)
            return parsed if isinstance(parsed, dict) else None
    except (OSError, json.JSONDecodeError) as exc:
        _log(f"send_event error: {exc}")
        return None


def build_payload(data: dict) -> dict | None:
    """Map a raw Claude hook event to SlopIsland's private protocol.

    Returns None for events we intentionally ignore.
    """
    event = data.get("hook_event_name", "")

    status_map = {
        "PermissionRequest": "waiting_for_approval",
        "UserPromptSubmit": "processing",
        "SessionStart": "idle",
        "Notification": "waiting_for_input",
        "Stop": "ended",
        "SessionEnd": "ended",
    }
    status = status_map.get(event)
    if status is None:
        return None

    payload: dict = {
        "event": event,
        "status": status,
        "session_id": data.get("session_id", ""),
        "cwd": data.get("cwd", ""),
        "transcript_path": data.get("transcript_path", ""),
    }

    tool_name = data.get("tool_name")
    if tool_name:
        payload["tool_name"] = tool_name
    tool_input = data.get("tool_input")
    if isinstance(tool_input, dict):
        payload["tool_input"] = tool_input
    if msg := data.get("message"):
        payload["message"] = msg
    if ntype := data.get("notification_type"):
        payload["notification_type"] = ntype

    return payload


def emit_permission_decision(response: dict | None) -> None:
    """Translate the app's decision into Claude Code's official hook output."""
    if not response:
        print("{}", flush=True)  # no decision -> let Claude show its own UI
        return

    decision = response.get("decision", "ask")
    reason = response.get("reason", "")

    if decision == "allow":
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        }
        print(json.dumps(out), flush=True)
    elif decision == "deny":
        out = {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {
                    "behavior": "deny",
                    "message": reason or "Denied via SlopIsland",
                },
            }
        }
        print(json.dumps(out), flush=True)
    else:
        print("{}", flush=True)  # "ask"/unknown -> fall back to Claude's UI


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print("{}", flush=True)
        return
    if not isinstance(data, dict):
        print("{}", flush=True)
        return

    payload = build_payload(data)
    if payload is None:
        print("{}", flush=True)
        return

    response = send_event(payload)

    if payload["status"] == "waiting_for_approval":
        emit_permission_decision(response)
    else:
        print("{}", flush=True)


if __name__ == "__main__":
    main()
