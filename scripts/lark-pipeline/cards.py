"""Lark interactive card definitions for InfiniLM-SVC build form."""

import json

# Build form card: user fills deployment_case, phase, pr_ref, include_smoke
# Button action value: build_image
BUILD_FORM_CARD = {
    "config": {"wide_screen_mode": True},
    "header": {
        "title": {"tag": "plain_text", "content": "InfiniLM-SVC Build Image"},
    },
    "elements": [
        {
            "tag": "div",
            "text": {"tag": "lark_md", "content": "Fill the form and click **Build** to run on private host."},
        },
        {
            "tag": "input",
            "name": "deployment_case",
            "label": {"tag": "plain_text", "content": "Deployment case"},
            "placeholder": {"tag": "plain_text", "content": "infinilm-metax-deployment-opt"},
        },
        {
            "tag": "select_static",
            "name": "phase",
            "label": {"tag": "plain_text", "content": "Build phase"},
            "options": [
                {"text": {"tag": "plain_text", "content": "dep-runtime"}, "value": "dep-runtime"},
                {"text": {"tag": "plain_text", "content": "build-runtime"}, "value": "build-runtime"},
                {"text": {"tag": "plain_text", "content": "runtime"}, "value": "runtime"},
            ],
        },
        {
            "tag": "input",
            "name": "pr_ref",
            "label": {"tag": "plain_text", "content": "PR (optional)"},
            "placeholder": {"tag": "plain_text", "content": "#42 or owner/repo#123"},
        },
        {
            "tag": "select_static",
            "name": "include_smoke",
            "label": {"tag": "plain_text", "content": "Run smoke validation"},
            "options": [
                {"text": {"tag": "plain_text", "content": "Yes"}, "value": "true"},
                {"text": {"tag": "plain_text", "content": "No"}, "value": "false"},
            ],
        },
        {
            "tag": "action",
            "actions": [
                {
                    "tag": "button",
                    "text": {"tag": "plain_text", "content": "Build"},
                    "type": "primary",
                    "value": {"action": "build_image"},
                },
            ],
        },
    ],
}


def get_build_form_card_json() -> str:
    """Return JSON string for the build form card."""
    return json.dumps(BUILD_FORM_CARD, ensure_ascii=False)
