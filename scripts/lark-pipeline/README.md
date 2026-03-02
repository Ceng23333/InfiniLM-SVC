# InfiniLM-SVC Lark Pipeline

Lark (Feishu) bot that triggers build-image and smoke validation on a private host via Fabric (SSH). Optionally posts results back to a GitHub PR.

## Architecture

```
User (Lark) --> webhook server (jump host) --> Fabric SSH --> private host
                                                       --> build-image.sh
                                                       --> docker run smoke
                webhook server --> (optional) GitHub API --> PR comment
```

## Setup

### 1. Lark App

1. Create an app at [Feishu Developer Console](https://open.feishu.cn)
2. Enable Event Subscription:
   - Event: `im.message.receive_v1`
   - Request URL: `https://<jump-host>/webhook`
   - Verification Token, Encrypt Key (optional)
3. Permissions: `im:message`, `im:message:send`, `im:message.receive_v1`
4. Publish the app

### 2. Jump Host

Install dependencies:

```bash
cd scripts/lark-pipeline
pip install -r requirements.txt
```

Copy and edit config:

```bash
cp .env.example .env
# Edit .env: APP_ID, APP_SECRET, VERIFICATION_TOKEN, PRIVATE_HOST, SSH_USER, SSH_KEY_PATH, REPO_PATH
```

Ensure the jump host can SSH to the private host (key-based auth). The private host must have:
- InfiniLM-SVC repo at `REPO_PATH`
- Docker
- `docker/metax/build-image.sh` executable

### 3. Run Webhook Server

```bash
cd scripts/lark-pipeline
python server.py
```

Or with systemd/supervisor. The server listens on `HOST:PORT` (default `0.0.0.0:8080`).

## Usage

Send messages to the Lark bot (group or DM):

| Command | Action |
|---------|--------|
| `build` | Run build-image.sh on private host |
| `pipeline` | Run build + smoke validation |
| `pipeline #42` | Same, and post result to PR #42 |
| `build owner/repo#123` | Same, for PR 123 in owner/repo |

## Optional: PR Notification

To post pipeline results to a GitHub PR:

1. Set `GITHUB_TOKEN` or `GITHUB_PAT` (Personal Access Token with `repo` scope)
2. Set `GITHUB_REPO` (default repo, e.g. `owner/repo`) when using `#42` style
3. Include PR reference in the command: `pipeline #42` or `build owner/repo#123`

## Manual Fabric Usage

From the `scripts/lark-pipeline` directory:

```bash
# Set env (or use .env)
export PRIVATE_HOST=user@host
export SSH_USER=user
export REPO_PATH=/path/to/InfiniLM-SVC

# Run pipeline via fab
fab -H $SSH_USER@$PRIVATE_HOST pipeline
```

Or use `run_pipeline()` from Python:

```python
from fabfile import run_pipeline
success, build_ok, smoke_ok, duration = run_pipeline()
```

## Environment Variables

See `.env.example` for full list. Key variables:

- `APP_ID`, `APP_SECRET`, `VERIFICATION_TOKEN` — Lark app credentials
- `PRIVATE_HOST`, `SSH_USER`, `SSH_KEY_PATH` — SSH to private host
- `REPO_PATH` — InfiniLM-SVC path on private host
- `GITHUB_TOKEN`, `GITHUB_REPO` — Optional PR notification
