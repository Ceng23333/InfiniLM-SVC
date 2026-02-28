#!/usr/bin/env bash
# Validate InfiniLM-SVC Master (registry, router, babysitter, 9g_8b_thinking)
# Run after start-master.sh; uses same REGISTRY_PORT/ROUTER_PORT as start-master.sh
#
# Usage:
#   ./validate.sh [REGISTRY_IP]
#   REGISTRY_PORT=18002 ROUTER_PORT=8002 ./validate.sh  # match start-master ports
#
# Exit: 0 if all checks pass, 1 otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_IP="${1:-localhost}"

# Load environment (same as start-master.sh)
if [ -f "${SCRIPT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
fi
if [ -f "${SCRIPT_DIR}/install.defaults.sh" ]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/install.defaults.sh"
fi

REGISTRY_PORT="${REGISTRY_PORT:-18000}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
BABYSITTER_HEALTH_PORT="${BABYSITTER_HEALTH_PORT:-8101}"

REGISTRY_URL="http://${REGISTRY_IP}:${REGISTRY_PORT}"
ROUTER_URL="http://${REGISTRY_IP}:${ROUTER_PORT}"
BABYSITTER_URL="http://${REGISTRY_IP}:${BABYSITTER_HEALTH_PORT}"

FAILED=0

echo "=========================================="
echo "Validating InfiniLM-SVC Master (9g_8b)"
echo "=========================================="
echo "Registry:   ${REGISTRY_URL}"
echo "Router:     ${ROUTER_URL}"
echo "Babysitter: ${BABYSITTER_URL}"
echo ""

# 1. Registry health
echo "[1/5] Registry health (${REGISTRY_URL}/health)"
RESP=$(curl -s -w "\n%{http_code}" --connect-timeout 5 "${REGISTRY_URL}/health" 2>/dev/null || echo -e "\n000")
HTTP_CODE=$(echo "${RESP}" | tail -1)
BODY=$(echo "${RESP}" | sed '$d')
if [ "${HTTP_CODE}" = "200" ]; then
  echo "${BODY}" | python3 -m json.tool 2>/dev/null || echo "${BODY}"
  echo "  -> OK"
else
  echo "${BODY}"
  echo "  -> FAILED (HTTP ${HTTP_CODE})"
  FAILED=1
fi
echo ""

# 2. Router health
echo "[2/5] Router health (${ROUTER_URL}/health)"
RESP=$(curl -s -w "\n%{http_code}" --connect-timeout 5 "${ROUTER_URL}/health" 2>/dev/null || echo -e "\n000")
HTTP_CODE=$(echo "${RESP}" | tail -1)
BODY=$(echo "${RESP}" | sed '$d')
if [ "${HTTP_CODE}" = "200" ]; then
  echo "${BODY}" | python3 -m json.tool 2>/dev/null || echo "${BODY}"
  echo "  -> OK"
else
  echo "${BODY}"
  echo "  -> FAILED (HTTP ${HTTP_CODE})"
  FAILED=1
fi
echo ""

# 3. Babysitter health
echo "[3/5] Babysitter health (${BABYSITTER_URL}/health)"
RESP=$(curl -s -w "\n%{http_code}" --connect-timeout 5 "${BABYSITTER_URL}/health" 2>/dev/null || echo -e "\n000")
HTTP_CODE=$(echo "${RESP}" | tail -1)
BODY=$(echo "${RESP}" | sed '$d')
if [ "${HTTP_CODE}" = "200" ]; then
  echo "${BODY}" | python3 -m json.tool 2>/dev/null || echo "${BODY}"
  echo "  -> OK"
else
  echo "${BODY}"
  echo "  -> FAILED (HTTP ${HTTP_CODE})"
  FAILED=1
fi
echo ""

# 4. Router models (9g_8b_thinking should be listed)
echo "[4/5] Router models (${ROUTER_URL}/models)"
MODELS=$(curl -s --connect-timeout 5 "${ROUTER_URL}/models" 2>/dev/null || echo "{}")
echo "${MODELS}" | python3 -m json.tool 2>/dev/null || echo "${MODELS}"
if echo "${MODELS}" | grep -q "9g_8b_thinking"; then
  echo "  -> OK (9g_8b_thinking)"
else
  echo "  -> FAILED (9g_8b_thinking not found)"
  FAILED=1
fi
echo ""

# 5. Chat completion (e2e)
echo "[5/5] Chat completion (POST ${ROUTER_URL}/v1/chat/completions)"
RESP=$(curl -s -X POST "${ROUTER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"9g_8b_thinking","messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
  --connect-timeout 5 --max-time 60 2>/dev/null || echo "")
echo "${RESP}" | python3 -m json.tool 2>/dev/null || echo "${RESP}"
if echo "${RESP}" | grep -q '"choices"'; then
  echo "  -> OK"
else
  echo "  -> FAILED"
  FAILED=1
fi

echo ""
if [ "${FAILED}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed."
  exit 1
fi
