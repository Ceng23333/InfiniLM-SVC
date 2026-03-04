#!/usr/bin/env python3
"""
Lark webhook server for InfiniLM-SVC pipeline.

Receives Lark bot messages, runs build+smoke on private host via Fabric,
sends reply to Lark, and optionally posts result to GitHub PR.

Env vars: see .env.example
"""

import json
import logging
import os
import re
import sys
import threading
from pathlib import Path

# Load .env before other imports
from dotenv import load_dotenv

_env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(_env_path)
load_dotenv()

# Map LARK_* to lark-oapi expected names
for lark_name, sdk_name in [
    ("LARK_APP_ID", "APP_ID"),
    ("LARK_APP_SECRET", "APP_SECRET"),
    ("LARK_VERIFICATION_TOKEN", "VERIFICATION_TOKEN"),
    ("LARK_ENCRYPT_KEY", "ENCRYPT_KEY"),
]:
    if os.environ.get(lark_name) and not os.environ.get(sdk_name):
        os.environ[sdk_name] = os.environ[lark_name]

logging.basicConfig(
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    level=logging.DEBUG if os.environ.get("DEBUG") else logging.INFO,
)
logger = logging.getLogger("lark-pipeline")

# Add script dir to path for fabfile import
_script_dir = Path(__file__).resolve().parent
if str(_script_dir) not in sys.path:
    sys.path.insert(0, str(_script_dir))


def _parse_command(text: str) -> tuple[str | None, str | None]:
    """
    Parse message text. Returns (action, pr_ref).
    action: 'build' | 'pipeline' | 'status' | None
    pr_ref: e.g. '42', 'owner/repo#123', or None
    """
    if not text or not isinstance(text, str):
        return None, None
    t = text.strip().lower()

    # PR patterns: #42, owner/repo#123, pr/123
    pr_ref = None
    m = re.search(r"#(\d+)", t)
    if m:
        pr_ref = m.group(1)
    m = re.search(r"([a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+)#(\d+)", t)
    if m:
        pr_ref = f"{m.group(1)}#{m.group(2)}"
    m = re.search(r"pr/(\d+)", t, re.I)
    if m:
        pr_ref = m.group(1)

    # Actions
    if t in ("build", "pipeline", "status", "card"):
        return t, pr_ref
    if t.startswith("build ") or t.startswith("pipeline ") or t.startswith("card "):
        action = "build" if t.startswith("build") else ("pipeline" if t.startswith("pipeline") else "card")
        return action, pr_ref
    if t.startswith("status "):
        return "status", pr_ref
    return None, None


def _post_to_github_pr(
    pr_ref: str, success: bool, build_ok: bool, smoke_ok: bool, duration: float
) -> bool:
    """Post pipeline result as PR comment."""
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_PAT")
    repo = os.environ.get("GITHUB_REPO")
    if not token or not repo:
        return False

    try:
        from github import Github

        gh = Github(token)
        if "#" in pr_ref:
            owner_repo, num = pr_ref.rsplit("#", 1)
            repo_obj = gh.get_repo(owner_repo)
        else:
            repo_obj = gh.get_repo(repo)
            num = pr_ref
        pr = repo_obj.get_pull(int(num))
        body = f"""## InfiniLM-SVC Pipeline (Private Host)

| Step | Result |
|------|--------|
| Build | {'OK' if build_ok else 'Fail'} |
| Smoke | {'OK' if smoke_ok else 'Fail'} |

**Duration:** {duration:.1f}s  
**Overall:** {'Success' if success else 'Failed'}
"""
        pr.create_issue_comment(body)
        return True
    except Exception as e:
        logger.exception("Failed to post to PR: %s", e)
        return False


def _send_lark_reply(client, message_id: str, text: str) -> None:
    """Reply to a Lark message."""
    try:
        from lark_oapi.api.im.v1.model.reply_message_request import ReplyMessageRequest
        from lark_oapi.api.im.v1.model.reply_message_request_body import (
            ReplyMessageRequestBody,
        )

        body = ReplyMessageRequestBody.builder().msg_type("text").content(
            json.dumps({"text": text})
        ).build()
        req = (
            ReplyMessageRequest.builder()
            .message_id(message_id)
            .request_body(body)
            .build()
        )
        resp = client.im.v1.message.reply(req)
        if resp.code != 0:
            logger.error("Lark reply failed: %s %s", resp.code, resp.msg)
    except Exception as e:
        logger.exception("Lark reply error: %s", e)


def _send_build_form_card(client, receive_id_type: str, receive_id: str) -> None:
    """Send the build form interactive card to a chat."""
    try:
        from lark_oapi.api.im.v1.model.create_message_request import CreateMessageRequest
        from lark_oapi.api.im.v1.model.create_message_request_body import (
            CreateMessageRequestBody,
        )

        from cards import get_build_form_card_json

        content = get_build_form_card_json()
        body = (
            CreateMessageRequestBody.builder()
            .receive_id(receive_id)
            .msg_type("interactive")
            .content(content)
            .build()
        )
        req = (
            CreateMessageRequest.builder()
            .receive_id_type(receive_id_type)
            .request_body(body)
            .build()
        )
        resp = client.im.v1.message.create(req)
        if resp.code != 0:
            logger.error("Lark send card failed: %s %s", resp.code, resp.msg)
    except Exception as e:
        logger.exception("Lark send card error: %s", e)


def _make_card_action_handler(client):
    """Build handler for card button clicks (form submit)."""

    def handler(data) -> "P2CardActionTriggerResponse":
        from lark_oapi.event.callback.model.p2_card_action_trigger import (
            P2CardActionTriggerResponse,
        )

        try:
            action_val = (data.event.action.value or {}) if data.event and data.event.action else {}
            if action_val.get("action") != "build_image":
                return P2CardActionTriggerResponse({})

            form = (data.event.action.form_value or {}) if data.event and data.event.action else {}
            deployment_case = str(form.get("deployment_case", "")).strip() or "infinilm-metax-deployment-opt"
            phase = str(form.get("phase", "")).strip() or "dep-runtime"
            pr_ref = str(form.get("pr_ref", "")).strip() or None
            include_smoke = str(form.get("include_smoke", "true")).lower() in ("true", "1", "yes")

            # Resolve receive target for result message
            ctx = data.event.context if data.event else None
            open_chat_id = ctx.open_chat_id if ctx else ""
            open_id = data.event.operator.open_id if data.event and data.event.operator else ""

            def run_and_notify():
                from fabfile import run_pipeline

                success, build_ok, smoke_ok, duration = run_pipeline(
                    deployment_case=deployment_case or None,
                    phase=phase or None,
                    include_smoke=include_smoke,
                )
                msg_text = (
                    f"Pipeline {'Success' if success else 'Failed'}\n"
                    f"Build: {'OK' if build_ok else 'Fail'}, Smoke: {'OK' if smoke_ok else 'Fail'}\n"
                    f"Duration: {duration:.1f}s"
                )
                _send_message_to_chat(client, open_chat_id, open_id, msg_text)
                if pr_ref and (os.environ.get("GITHUB_TOKEN") or os.environ.get("GITHUB_PAT")):
                    ok = _post_to_github_pr(pr_ref, success, build_ok, smoke_ok, duration)
                    if ok:
                        _send_message_to_chat(client, open_chat_id, open_id, f"Posted result to PR {pr_ref}")

            t = threading.Thread(target=run_and_notify)
            t.daemon = True
            t.start()

            return P2CardActionTriggerResponse({
                "toast": {
                    "type": "info",
                    "content": "Build started...",
                    "i18n": {"zh_cn": "构建已启动...", "en_us": "Build started..."},
                },
            })
        except Exception as e:
            logger.exception("Card action handler error: %s", e)
            return P2CardActionTriggerResponse({
                "toast": {"type": "danger", "content": str(e)[:100]},
            })

    return handler


def _send_message_to_chat(client, chat_id: str, open_id: str, text: str) -> None:
    """Send a text message to chat (by chat_id or open_id)."""
    try:
        from lark_oapi.api.im.v1.model.create_message_request import CreateMessageRequest
        from lark_oapi.api.im.v1.model.create_message_request_body import (
            CreateMessageRequestBody,
        )

        rid_type = "chat_id" if chat_id else "open_id"
        rid = chat_id or open_id
        if not rid:
            return
        body = (
            CreateMessageRequestBody.builder()
            .receive_id(rid)
            .msg_type("text")
            .content(json.dumps({"text": text}))
            .build()
        )
        req = (
            CreateMessageRequest.builder()
            .receive_id_type(rid_type)
            .request_body(body)
            .build()
        )
        resp = client.im.v1.message.create(req)
        if resp.code != 0:
            logger.error("Lark send message failed: %s %s", resp.code, resp.msg)
    except Exception as e:
        logger.exception("Lark send message error: %s", e)


def _make_message_handler(client):
    """Build handler that closes over client for sending replies."""

    def handler(event: "P2ImMessageReceiveV1") -> None:
        try:
            msg = event.event.message if event.event else None
            if not msg or msg.message_type != "text":
                return
            content = msg.content or "{}"
            try:
                content_obj = json.loads(content) if isinstance(content, str) else content
                text = content_obj.get("text", "").strip()
            except Exception:
                text = str(content)

            action, pr_ref = _parse_command(text)
            if not action:
                return

            message_id = msg.message_id
            chat_type = msg.chat_type or "p2p"
            chat_id = msg.chat_id or ""
            open_id = (event.event.sender.sender_id.open_id if event.event and event.event.sender else "") or ""

            # Send interactive form card for build/pipeline/card
            if action in ("build", "pipeline", "card"):
                if chat_type == "group" and chat_id:
                    _send_build_form_card(client, "chat_id", chat_id)
                else:
                    _send_build_form_card(client, "open_id", open_id)
                return

            # Legacy: status or direct run (e.g. from parsed "status" - no-op for now)
            if action == "status":
                _send_lark_reply(client, message_id, "Send 'build' or 'card' to get the build form.")
                return

        except Exception as e:
            logger.exception("Message handler error: %s", e)

    return handler


def create_app():
    """Create Flask app with Lark webhook route."""
    from flask import Flask, make_response, request

    from lark_oapi import Client
    from lark_oapi.adapter.flask.parser import parse_req, parse_resp
    from lark_oapi.event.dispatcher_handler import EventDispatcherHandler
    from lark_oapi.event.dispatcher_handler import EventDispatcherHandlerBuilder

    app_id = os.environ.get("APP_ID") or os.environ.get("LARK_APP_ID")
    app_secret = os.environ.get("APP_SECRET") or os.environ.get("LARK_APP_SECRET")
    verification_token = os.environ.get("VERIFICATION_TOKEN") or os.environ.get(
        "LARK_VERIFICATION_TOKEN"
    )
    encrypt_key = os.environ.get("ENCRYPT_KEY") or os.environ.get("LARK_ENCRYPT_KEY") or ""

    if not all([app_id, app_secret, verification_token]):
        raise ValueError("APP_ID, APP_SECRET, VERIFICATION_TOKEN are required")

    # Client for sending messages
    client = Client.builder().app_id(app_id).app_secret(app_secret).build()

    # Card action handler (form submit)
    card_handler = _make_card_action_handler(client)

    # Event handler
    msg_handler = _make_message_handler(client)
    event_handler = (
        EventDispatcherHandler.builder(encrypt_key, verification_token)
        .register_p2_im_message_receive_v1(msg_handler)
        .register_p2_card_action_trigger(card_handler)
        .build()
    )

    app = Flask(__name__)

    @app.route("/webhook", methods=["GET", "POST"])
    def webhook():
        raw_req = parse_req()
        raw_resp = event_handler.do(raw_req)
        return parse_resp(raw_resp)

    # Card callbacks may use a separate URL in Feishu app config
    @app.route("/card", methods=["GET", "POST"])
    def card():
        raw_req = parse_req()
        raw_resp = event_handler.do(raw_req)
        return parse_resp(raw_resp)

    return app


def main():
    if "--help" in sys.argv or "-h" in sys.argv:
        print(__doc__)
        print("Env: LARK_APP_ID, LARK_APP_SECRET, LARK_VERIFICATION_TOKEN, PRIVATE_HOST, SSH_USER, ...")
        sys.exit(0)

    try:
        from flask import Flask
    except ImportError:
        print("Install: pip install lark-oapi[flask] fabric python-dotenv PyGithub")
        sys.exit(1)

    app = create_app()
    port = int(os.environ.get("PORT", "8080"))
    host = os.environ.get("HOST", "0.0.0.0")
    logger.info("Starting webhook server on %s:%d", host, port)
    app.run(host=host, port=port, debug=bool(os.environ.get("DEBUG")))


if __name__ == "__main__":
    main()
