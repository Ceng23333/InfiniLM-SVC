#!/usr/bin/env python3
"""
Fabric tasks for InfiniLM-SVC Lark pipeline.

Runs build-image and smoke validation on a private host via SSH.
Use from the webhook server or CLI: fab -H user@host pipeline

Environment variables (or .env):
  REPO_PATH          Path to InfiniLM-SVC on private host
  DEPLOYMENT_CASE    Deployment case (default: infinilm-metax-deployment-opt)
  IMAGE_TAG          Output image tag (default: infinilm-svc:infinilm-demo)
  HTTP_PROXY         Optional proxy for build
"""

import os
import time
from pathlib import Path

from fabric import Connection, task
from dotenv import load_dotenv

# Load .env from script directory or current dir
_env_path = Path(__file__).resolve().parent / ".env"
load_dotenv(_env_path)
load_dotenv()


def _get_config() -> dict:
    """Build Fabric connect_kwargs from environment."""
    cfg = {}
    key_path = os.environ.get("SSH_KEY_PATH")
    if key_path and os.path.exists(os.path.expanduser(key_path)):
        cfg["key_filename"] = os.path.expanduser(key_path)
    password = os.environ.get("SSH_PASSWORD")
    if password:
        cfg["password"] = password
    return cfg


def _conn() -> Connection:
    host = os.environ.get("PRIVATE_HOST")
    user = os.environ.get("SSH_USER", "root")
    if not host:
        raise ValueError("PRIVATE_HOST is required")
    return Connection(
        host=host,
        user=user,
        connect_kwargs=_get_config(),
    )


def _build_cmd() -> str:
    repo = os.environ.get("REPO_PATH", "/home/zenghua/repos/InfiniLM-SVC")
    case = os.environ.get("DEPLOYMENT_CASE", "infinilm-metax-deployment-opt")
    phase = os.environ.get("BUILD_PHASE", "dep-runtime")
    proxy = os.environ.get("HTTP_PROXY", "")
    parts = [
        f"cd {repo}",
        "&& ./docker/metax/build-image.sh",
        f"--phase {phase}",
        f"--deployment-case {case}",
    ]
    if proxy:
        parts.append(f"--proxy {proxy}")
    return " ".join(parts)


def _smoke_cmd() -> str:
    tag = os.environ.get("IMAGE_TAG", "infinilm-svc:infinilm-demo")
    return (
        f"docker run --rm --entrypoint '' {tag} infini-router --help"
    )


def _run_build(c: Connection) -> bool:
    """Run build-image.sh. Returns True on success."""
    result = c.run(_build_cmd(), warn=True)
    return result.exited == 0


def _run_smoke(c: Connection) -> bool:
    """Run smoke check. Returns True on success."""
    result = c.run(_smoke_cmd(), warn=True)
    return result.exited == 0


def run_pipeline(
    deployment_case: str | None = None,
    phase: str | None = None,
    include_smoke: bool = True,
) -> tuple[bool, bool, bool, float]:
    """
    Run build then smoke on private host. Returns (success, build_ok, smoke_ok, duration_sec).
    Call from webhook server. Overrides for deployment_case, phase, include_smoke.
    """
    saved = {}
    if deployment_case is not None:
        saved["DEPLOYMENT_CASE"] = os.environ.get("DEPLOYMENT_CASE")
        os.environ["DEPLOYMENT_CASE"] = deployment_case
    if phase is not None:
        saved["BUILD_PHASE"] = os.environ.get("BUILD_PHASE")
        os.environ["BUILD_PHASE"] = phase
    try:
        c = _conn()
        start = time.time()
        try:
            build_ok = _run_build(c)
            smoke_ok = _run_smoke(c) if build_ok and include_smoke else True
        finally:
            c.close()
        duration = time.time() - start
        success = build_ok and (smoke_ok if include_smoke else True)
        return success, build_ok, smoke_ok, duration
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v
            elif k in os.environ:
                del os.environ[k]


@task
def build(c):
    """Run build-image.sh on the private host."""
    return _run_build(c)


@task
def smoke(c):
    """Run a light smoke check: docker run image infini-router --help."""
    return _run_smoke(c)


@task
def pipeline(c):
    """Run build then smoke. For CLI: fab pipeline (uses PRIVATE_HOST from env)."""
    start = time.time()
    build_ok = _run_build(c)
    smoke_ok = _run_smoke(c) if build_ok else False
    duration = time.time() - start
    print(f"Build: {'OK' if build_ok else 'FAIL'}, Smoke: {'OK' if smoke_ok else 'FAIL'}, Duration: {duration:.1f}s")
    return build_ok and smoke_ok
