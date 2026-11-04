#!/usr/bin/env bash
# ==============================================================================
# JimoTable Community Free Edition - Zero-Friction Quickstart Script
# ==============================================================================
set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELFHOST_SCRIPT="$SCRIPT_DIR/selfhost/jimotable.sh"
ENV_FILE="$SCRIPT_DIR/.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_succ() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()      { log_err "$*"; exit 1; }


echo -e "${BOLD}"
cat <<'BANNER'
       _ _             _____     _     _      
      (_) |           |_   _|   | |   | |     
       _| |_ __  ___    | | __ _| |__ | | ___ 
      | | | '_ ` _ \   | |/ _` | '_ \| |/ _ \
      | | | | | | | |  | | (_| | |_) | |  __/
     _/ |_|_| |_| |_|  \_/\__,_|_.__/|_|\___|
    |__/                                      
BANNER
echo -e "${NC}${BLUE}The Postgres-backed Data Runtime for AI Agents, with Human-in-the-loop UI${NC}\n"

# 1. Check prerequisites
command -v docker >/dev/null 2>&1 || die "Docker is not installed. Please visit https://docs.docker.com/get-docker/ to install Docker."
docker compose version >/dev/null 2>&1 || die "Docker Compose (v2) is not available. Please ensure Docker Compose plugin is installed."
command -v curl >/dev/null 2>&1 || die "Missing required command: curl"
command -v jq >/dev/null 2>&1 || die "Missing required command: jq"
command -v openssl >/dev/null 2>&1 || die "Missing required command: openssl"

[[ -x "$SELFHOST_SCRIPT" ]] || chmod +x "$SELFHOST_SCRIPT" 2>/dev/null || true
[[ -f "$SELFHOST_SCRIPT" ]] || die "Missing core operational script: $SELFHOST_SCRIPT"

# 2. Initialize configuration and secrets
log_info "1/4 Initializing deployment configuration and secrets..."
"$SELFHOST_SCRIPT" init

resolve_http_port() {
  local port=""
  if [[ -f "$ENV_FILE" ]]; then
    port="$(sed -n 's/^JIMOTABLE_HTTP_PORT=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
  fi
  if [[ -z "$port" && -f "$SCRIPT_DIR/.env.example" ]]; then
    port="$(sed -n 's/^JIMOTABLE_HTTP_PORT=//p' "$SCRIPT_DIR/.env.example" | tail -1 | tr -d '\r\n')"
  fi
  echo "${port:-8080}"
}

PORT="$(resolve_http_port)"

# 3. Start containers
log_info "2/4 Starting JimoTable containers..."
"$SELFHOST_SCRIPT" up

# 4. Wait for services to become healthy
HEALTH_URL="http://127.0.0.1:${PORT}/actuator/health"
log_info "3/4 Waiting for API service to become healthy (url: $HEALTH_URL)..."

MAX_RETRIES=45
COUNT=0
HEALTHY=false

while (( COUNT < MAX_RETRIES )); do
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  printf "."
  sleep 2
  COUNT=$((COUNT + 1))
done
echo ""

if [[ "$HEALTHY" != "true" ]]; then
  log_err "API health check timed out after ${MAX_RETRIES} attempts."
  log_err "Run the following command to check logs:"
  log_err "  $SELFHOST_SCRIPT logs"
  exit 1
fi
log_succ "JimoTable service passed health checks!"

# 5. Bootstrap admin credentials & verify stack
log_info "4/4 Bootstrapping operator credentials and verifying stack..."
"$SELFHOST_SCRIPT" bootstrap
"$SELFHOST_SCRIPT" verify

# 6. Print welcoming completion banner
cat <<EOF

================================================================================
${GREEN}${BOLD}🎉 JimoTable Community Free Edition is up and running!${NC}
================================================================================

👉 ${BOLD}Web Console:${NC}         http://localhost:${PORT}
👉 ${BOLD}Health Check:${NC}        http://localhost:${PORT}/actuator/health
👉 ${BOLD}Operator Credential:${NC} ${SCRIPT_DIR}/selfhost/operator.json

${BOLD}Accessing your admin token:${NC}
Run the following command to securely display the operator token:
  ${BLUE}${SELFHOST_SCRIPT} operator-show --yes${NC}

${BOLD}Next steps:${NC}
1. Open http://localhost:${PORT} to access the data console.
2. Read the simulated workflow (prints only; no data is created):
   ${BLUE}./demo/simulate-agent.sh${NC}
3. Install the Agent workspace skill (Cursor / Claude Code):
   ${BLUE}Read skills/jimotable-workspace/SKILL.md (local skill; remote installer not yet verified)${NC}

${BOLD}Useful operational commands:${NC}
- Stack status:  ${SELFHOST_SCRIPT} status
- View logs:     ${SELFHOST_SCRIPT} logs
- Take backup:   ${SELFHOST_SCRIPT} backup
- Stop services: ${SELFHOST_SCRIPT} down
================================================================================
EOF

