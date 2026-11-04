#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  workspace-api.sh check
  workspace-api.sh openapi
  workspace-api.sh request METHOD PATH [JSON_OR_@FILE] [IDEMPOTENCY_KEY]

Required environment:
  JIMOTABLE_API_URL
  JIMOTABLE_AGENT_USER_TOKEN

PATH is relative to /agent-api/v1/workspace and must start with '/'.
USAGE
}

fail() {
  printf 'workspace-api: %s\n' "$*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_command curl
require_command jq

api_url="${JIMOTABLE_API_URL:-}"
agent_token="${JIMOTABLE_AGENT_USER_TOKEN:-}"
timeout_seconds="${JIMOTABLE_HTTP_TIMEOUT_SECONDS:-30}"

[[ -n "$api_url" ]] || fail 'JIMOTABLE_API_URL is required'
[[ -n "$agent_token" ]] || fail 'JIMOTABLE_AGENT_USER_TOKEN is required'
[[ "$api_url" != *$'\n'* && "$api_url" != *$'\r'* ]] \
  || fail 'JIMOTABLE_API_URL must not contain line breaks'
[[ "$agent_token" != *$'\n'* && "$agent_token" != *$'\r'* ]] \
  || fail 'JIMOTABLE_AGENT_USER_TOKEN must not contain line breaks'
[[ "$api_url" == http://* || "$api_url" == https://* ]] \
  || fail 'JIMOTABLE_API_URL must start with http:// or https://'
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] \
  || fail 'JIMOTABLE_HTTP_TIMEOUT_SECONDS must be a positive integer'

api_url="${api_url%/}"
workspace_prefix='/agent-api/v1/workspace'

perform_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local idempotency_key="${4:-}"

  [[ "$method" =~ ^(GET|POST|PUT|PATCH|DELETE)$ ]] \
    || fail "unsupported HTTP method: $method"
  [[ "$path" == /* ]] || fail "request path must start with '/': $path"
  [[ "$path" != //* && "$path" != *://* ]] \
    || fail 'absolute or scheme-relative request paths are not allowed'
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] \
    || fail 'request path must not contain line breaks'
  [[ "$path" != /../* && "$path" != */../* && "$path" != */.. ]] \
    || fail 'request path must not contain parent-directory segments'

  if [[ -n "$idempotency_key" ]]; then
    [[ ${#idempotency_key} -le 128 ]] \
      || fail 'Idempotency-Key must be at most 128 characters'
    [[ "$idempotency_key" != *$'\n'* && "$idempotency_key" != *$'\r'* ]] \
      || fail 'Idempotency-Key must not contain line breaks'
  fi

  local body_file=''
  if [[ -n "$body" && "$body" == @* ]]; then
    body_file="${body#@}"
    [[ -f "$body_file" ]] || fail "JSON body file does not exist: $body_file"
    jq -e . "$body_file" >/dev/null 2>&1 || fail "invalid JSON body file: $body_file"
  elif [[ -n "$body" ]]; then
    jq -e . <<<"$body" >/dev/null 2>&1 || fail 'inline request body is not valid JSON'
  fi

  local request_dir response_file auth_header_file
  request_dir="$(mktemp -d "${TMPDIR:-/tmp}/jimotable-workspace.XXXXXX")"
  response_file="$request_dir/response.json"
  auth_header_file="$request_dir/authorization.header"
  printf 'Authorization: Bearer %s\n' "$agent_token" >"$auth_header_file"
  chmod 600 "$auth_header_file"
  trap 'rm -rf -- "$request_dir"; exit 130' HUP INT TERM
  local -a curl_args=(
    --silent --show-error
    --max-time "$timeout_seconds"
    --request "$method"
    --header "@$auth_header_file"
    --header 'Accept: application/json'
    --output "$response_file"
    --write-out '%{http_code}'
  )

  if [[ -n "$idempotency_key" ]]; then
    curl_args+=(--header "Idempotency-Key: $idempotency_key")
  fi

  if [[ -n "$body" ]]; then
    curl_args+=(--header 'Content-Type: application/json')
    if [[ "$body" == @* ]]; then
      curl_args+=(--data-binary "@$body_file")
    else
      curl_args+=(--data-binary "$body")
    fi
  fi

  local status
  if ! status="$(curl "${curl_args[@]}" "$api_url$workspace_prefix$path")"; then
    rm -rf -- "$request_dir"
    trap - HUP INT TERM
    return 1
  fi

  if [[ -s "$response_file" ]]; then
    cat "$response_file"
    printf '\n'
  fi
  rm -rf -- "$request_dir"
  trap - HUP INT TERM

  if [[ ! "$status" =~ ^2[0-9][0-9]$ ]]; then
    printf 'workspace-api: HTTP %s for %s %s\n' "$status" "$method" "$path" >&2
    return 1
  fi
}

command_name="${1:-}"
case "$command_name" in
  check)
    if ! openapi_json="$(perform_request GET /openapi.json)"; then
      [[ -z "$openapi_json" ]] || printf '%s\n' "$openapi_json"
      exit 1
    fi
    jq '{
      status: "ready",
      title: .info.title,
      version: .info.version,
      quotaSubject: ."x-jimotable-quota-subject",
      operations: [.paths[] | to_entries[] | .value.operationId // empty] | sort
    }' <<<"$openapi_json"
    ;;
  openapi)
    perform_request GET /openapi.json
    ;;
  request)
    [[ $# -ge 3 && $# -le 5 ]] || { usage; exit 2; }
    perform_request "$2" "$3" "${4:-}" "${5:-}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
