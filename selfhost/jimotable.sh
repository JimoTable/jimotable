#!/usr/bin/env bash
# Single-quoted programs are intentionally evaluated by the target container;
# SHA256SUMS is explicitly excluded from the file list that feeds its output.
# shellcheck disable=SC2016,SC2094
set -Eeuo pipefail
umask 077

SELFHOST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SELFHOST_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/docker-compose.free.yml"
SECRETS_DIR="$SELFHOST_DIR/secrets"
BACKUPS_DIR="$SELFHOST_DIR/backups"
OPERATOR_FILE="$SELFHOST_DIR/operator.json"
STAGE_FILE="$SELFHOST_DIR/.bootstrap.stage"

resolve_project_name() {
  if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    echo "$COMPOSE_PROJECT_NAME"
    return
  fi
  if [[ -f "$ENV_FILE" ]]; then
    local env_name
    env_name="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
    if [[ -n "$env_name" ]]; then
      echo "$env_name"
      return
    fi
  fi
  if [[ -f "$COMPOSE_FILE" ]]; then
    local raw_name
    raw_name="$(sed -n 's/^name:[[:space:]]*//p' "$COMPOSE_FILE" | head -1 | tr -d '\r\n')"
    if [[ -n "$raw_name" ]]; then
      echo "$raw_name"
      return
    fi
  fi
  echo "jimotable-free"
}

PROJECT_NAME="$(resolve_project_name)"
[[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "错误：无法解析有效项目名：$PROJECT_NAME" >&2; exit 1; }

compose() {
  docker compose -p "$PROJECT_NAME" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

postgres_image() {
  compose config --format json | jq -er '.services.postgres.image'
}

postgres_major() {
  local version_num
  version_num="$(compose exec -T postgres psql -U jimotable_owner -d jimotable \
    -Atc 'SHOW server_version_num')"
  [[ "$version_num" =~ ^[0-9]+$ ]] || die "无法确认 PostgreSQL 大版本"
  echo "$((version_num / 10000))"
}

die() { echo "错误：$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

secret_files=(postgres_password runtime_db_password worker_db_password
  credential_digest_key internal_jwt_key cursor_key bootstrap_secret)

check_secret_state() {
  local missing=0 file
  for file in "${secret_files[@]}"; do
    [[ -s "$SECRETS_DIR/$file" ]] || { echo "缺少密钥：$file" >&2; missing=1; }
  done
  (( missing == 0 )) || die "请从匹配的备份恢复 selfhost/secrets，禁止为已有数据库重建密钥"
}

random_hex() { openssl rand -hex "$1"; }
random_base64() { openssl rand -base64 "$1" | tr -d '\r\n'; }

init() {
  require_command docker
  require_command openssl
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "已创建 $ENV_FILE"
  fi

  local has_any=false file
  for file in "${secret_files[@]}"; do
    [[ ! -e "$SECRETS_DIR/$file" ]] || has_any=true
  done
  if docker volume inspect "${PROJECT_NAME}_postgres-data" >/dev/null 2>&1; then
    check_secret_state
    echo "已有数据库卷和匹配密钥；未做修改。"
    return
  fi
  if [[ "$has_any" == true ]]; then
    check_secret_state
    echo "已有完整密钥；未做修改。"
    return
  fi

  umask 077
  mkdir -p "$SECRETS_DIR" "$BACKUPS_DIR"
  chmod 700 "$SECRETS_DIR" "$BACKUPS_DIR"
  random_hex 32 > "$SECRETS_DIR/postgres_password"
  random_hex 32 > "$SECRETS_DIR/runtime_db_password"
  random_hex 32 > "$SECRETS_DIR/worker_db_password"
  random_base64 48 > "$SECRETS_DIR/credential_digest_key"
  random_base64 48 > "$SECRETS_DIR/internal_jwt_key"
  random_base64 48 > "$SECRETS_DIR/cursor_key"
  random_base64 48 > "$SECRETS_DIR/bootstrap_secret"
  chmod 600 "$SECRETS_DIR"/*
  touch "$SELFHOST_DIR/.initialized"
  chmod 600 "$SELFHOST_DIR/.initialized"
  echo "已生成部署配置和密钥。下一步：./selfhost/jimotable.sh up"
}

ensure_initialized() {
  [[ -f "$ENV_FILE" ]] || die "尚未初始化，请先运行 $0 init"
  check_secret_state
}

pull_or_build() {
  local image version full_image
  image="$(sed -n 's/^JIMOTABLE_IMAGE=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
  version="$(sed -n 's/^JIMOTABLE_VERSION=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
  full_image="${image:-ghcr.io/jimotable/jimotable}:${version:-0.2.1}"

  if compose pull api worker 2>/dev/null; then
    return 0
  fi

  if docker image inspect "$full_image" >/dev/null 2>&1; then
    echo "提示：远端镜像拉取未成功，检测到本地已存在 ${full_image}；继续使用该镜像。" >&2
    return 0
  fi

  die "镜像拉取失败，且本地 Docker 不存在镜像 ${full_image}；请检查网络或配置"
}

run_db_init() {
  compose up -d --wait postgres
  compose up -d --no-deps --force-recreate db-init
  compose wait db-init
}

up() {
  ensure_initialized
  pull_or_build
  run_db_init
  compose up -d --wait api worker
  status
}

down() { ensure_initialized; compose down; }

operator_seconds_left() {
  [[ -s "$OPERATOR_FILE" ]] || return 1
  local expires now
  expires="$(jq -r '.expiresAt // empty' "$OPERATOR_FILE")"
  [[ -n "$expires" ]] || return 1
  now="$(date -u +%s)"
  echo $(( $(jq -nr --arg value "$expires" '$value | fromdateiso8601') - now ))
}

status() {
  ensure_initialized
  compose ps
  if [[ -s "$OPERATOR_FILE" ]]; then
    local left
    left="$(operator_seconds_left || echo 0)"
    if (( left < 0 )); then
      echo "警告：operator 凭证已过期。" >&2
    elif (( left < 30 * 86400 )); then
      echo "警告：operator 凭证将在 $((left / 86400)) 天内过期，请运行 operator-rotate。" >&2
    fi
  else
    echo "提示：尚未保存 operator 凭证，请运行 bootstrap。" >&2
  fi
}

expires_in_365_days() {
  if date -u -v+365d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -v+365d +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -d '+365 days' +%Y-%m-%dT%H:%M:%SZ
  fi
}

set_stage() {
  local stage="$1" tmp
  tmp="$(mktemp "$SELFHOST_DIR/.stage.XXXXXX")"
  echo "$stage" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$STAGE_FILE"
}

get_stage() {
  [[ -f "$STAGE_FILE" ]] && tr -d '\r\n' < "$STAGE_FILE" || echo ""
}

clear_stage() {
  rm -f "$STAGE_FILE"
}

operator_authenticated() {
  jq -er '.secret' "$OPERATOR_FILE" | compose exec -T api sh -c '
    IFS= read -r token
    printf "header = \"Authorization: Bearer %s\"\n" "$token" \
      | curl --fail --silent --config - http://127.0.0.1:8080/v1/session
  ' | jq -e '.operator == true' >/dev/null 2>&1
}

finish_bootstrap() {
  local stage="$1" tmp
  case "$stage" in
    ""|STAGE_INIT|STAGE_CREDENTIAL_SAVED|STAGE_SECRET_ROTATED|STAGE_API_RELOADED) ;;
    *) die "未知 bootstrap 阶段；已保留凭证和阶段文件，请检查后恢复" ;;
  esac

  # Authenticate before changing secrets, and again after the API reload.
  compose up -d --wait api >/dev/null
  operator_authenticated \
    || die "operator 凭证鉴权失败；已保留凭证和 bootstrap 阶段，请从匹配备份恢复"

  # STAGE_INIT + operator.json is the crash window between the two renames.
  # Never promote an old .new file: it may contain a partially written secret.
  if [[ "$stage" == STAGE_INIT || "$stage" == STAGE_CREDENTIAL_SAVED \
      || -e "$SECRETS_DIR/bootstrap_secret.new" ]]; then
    set_stage STAGE_CREDENTIAL_SAVED
    tmp="$(mktemp "$SECRETS_DIR/.bootstrap-secret.XXXXXX")"
    random_base64 48 > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$SECRETS_DIR/bootstrap_secret.new"
    mv "$SECRETS_DIR/bootstrap_secret.new" "$SECRETS_DIR/bootstrap_secret"
    set_stage STAGE_SECRET_ROTATED
    stage=STAGE_SECRET_ROTATED
  fi

  if [[ "$stage" != STAGE_API_RELOADED ]]; then
    compose up -d --no-deps --force-recreate --wait api >/dev/null
    set_stage STAGE_API_RELOADED
  fi
  operator_authenticated \
    || die "API 重载后 operator 鉴权失败；已保留 bootstrap 阶段，请检查后重试"
  clear_stage
}

bootstrap() {
  ensure_initialized
  require_command jq

  local lock_file="$SELFHOST_DIR/.bootstrap.lock"
  local lock_dir="$SELFHOST_DIR/.bootstrap.lock.dir"
  local have_flock=false
  if command -v flock >/dev/null 2>&1; then
    have_flock=true
    touch "$lock_file"
    chmod 600 "$lock_file"
    exec 200<"$lock_file"
    if ! flock -n 200; then
      die "另一个 bootstrap 正在进行"
    fi
  else
    if ! mkdir "$lock_dir" 2>/dev/null; then
      die "另一个 bootstrap 正在进行"
    fi
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
  fi

  release_lock() {
    if [[ "$have_flock" == true ]]; then
      flock -u 200
      exec 200<&-
    else
      rmdir "$lock_dir" 2>/dev/null || true
      trap - EXIT
    fi
  }

  local stage
  stage="$(get_stage)"

  if [[ -e "$OPERATOR_FILE" ]]; then
    if ! jq -e '(.id | type == "string" and length > 0)
        and (.secret | type == "string" and length > 0)
        and (.expiresAt | type == "string" and length > 0)
        and .kind == "OPERATOR"' "$OPERATOR_FILE" >/dev/null 2>&1; then
      die "operator.json 存在但已损坏；已保留原文件，请从备份恢复"
    fi

    if [[ -n "$stage" || -e "$SECRETS_DIR/bootstrap_secret.new" ]]; then
      echo "检测到此前 bootstrap 中断，开始断点恢复..."
      finish_bootstrap "$stage"
      echo "断点恢复完成：bootstrap 密钥已轮换，API 与 operator 凭证验证通过。"
    else
      compose up -d --wait api >/dev/null
      operator_authenticated \
        || die "operator.json 存在但鉴权失败或已失效；已保留原文件，请从备份恢复"
      echo "operator 凭证已存在且有效；未做修改。"
    fi
    release_lock
    return 0
  fi

  compose up -d --wait api
  set_stage "STAGE_INIT"

  local tmp expires curl_out
  tmp="$(mktemp "$SELFHOST_DIR/.operator.XXXXXX")"
  expires="$(expires_in_365_days)"

  if ! curl_out="$(compose exec -T api sh -c '
      IFS= read -r secret
      printf "header = \"Content-Type: application/json\"\nheader = \"X-Jimo-Bootstrap-Secret: %s\"\n" "$secret" \
        | curl --fail-with-body --silent --show-error --config - \
            -d "$1" http://127.0.0.1:8080/v1/auth/bootstrap
    ' sh "{\"displayName\":\"Self-host operator\",\"expiresAt\":\"$expires\"}" < "$SECRETS_DIR/bootstrap_secret")"; then
    rm -f "$tmp"
    clear_stage
    if echo "$curl_out" | grep -qiE "already|conflict|409"; then
      die "数据库已存在初始化凭证，但本地缺少 operator.json。服务端无法重新生成已保存凭证，请从备份恢复 operator.json。"
    fi
    die "bootstrap 失败：$curl_out"
  fi

  echo "$curl_out" > "$tmp"
  jq -e '.id and .secret and .expiresAt and .kind == "OPERATOR"' "$tmp" >/dev/null \
    || { rm -f "$tmp"; clear_stage; die "bootstrap 返回无效响应；未输出敏感响应内容"; }
  chmod 600 "$tmp"
  mv "$tmp" "$OPERATOR_FILE"
  set_stage "STAGE_CREDENTIAL_SAVED"

  finish_bootstrap STAGE_CREDENTIAL_SAVED
  release_lock
  echo "operator 凭证已安全保存到 selfhost/operator.json；bootstrap secret 已轮换。"
}

operator_show() {
  [[ "${1:-}" == "--yes" ]] || die "查看原始凭证必须显式运行：$0 operator-show --yes"
  [[ -s "$OPERATOR_FILE" ]] || die "operator.json 不存在"
  cat "$OPERATOR_FILE"
}

operator_rotate() {
  ensure_initialized
  require_command jq
  [[ -s "$OPERATOR_FILE" ]] || die "operator.json 不存在，请先 bootstrap 或恢复备份"
  local id expires payload tmp
  id="$(jq -r '.id' "$OPERATOR_FILE")"
  expires="$(expires_in_365_days)"
  payload="{\"displayName\":\"Self-host operator\",\"expiresAt\":\"$expires\",\"overlapSeconds\":600}"
  tmp="$(mktemp "$SELFHOST_DIR/.operator.XXXXXX")"
  if ! jq -r '.secret' "$OPERATOR_FILE" | compose exec -T api sh -c '
      IFS= read -r token
      printf "header = \"Content-Type: application/json\"\nheader = \"Authorization: Bearer %s\"\n" "$token" \
        | curl --fail-with-body --silent --show-error --config - \
            -d "$2" "http://127.0.0.1:8080/v1/operator/credentials/$1/rotate"
    ' sh "$id" "$payload" > "$tmp"; then
    rm -f "$tmp"; die "operator 轮换失败"
  fi
  jq -e '.id and .secret and .expiresAt' "$tmp" >/dev/null \
    || { rm -f "$tmp"; die "operator 轮换返回无效响应"; }
  cp "$OPERATOR_FILE" "$OPERATOR_FILE.previous"
  chmod 600 "$OPERATOR_FILE.previous" "$tmp"
  mv "$tmp" "$OPERATOR_FILE"
  echo "operator 已轮换；旧凭证保留 10 分钟，快照位于 operator.json.previous。"
}

verify() {
  ensure_initialized
  require_command jq
  require_command curl
  local failed=0 left
  [[ -n "$(compose ps --status running -q postgres)" ]] || { echo "PostgreSQL 未运行" >&2; failed=1; }

  local api_id api_status
  api_id="$(compose ps -q api || true)"
  [[ -n "$api_id" ]] || { echo "API 未运行" >&2; failed=1; }
  if [[ -n "$api_id" ]]; then
    api_status="$(docker inspect --format '{{.State.Health.Status}}' "$api_id" 2>/dev/null || true)"
    [[ "$api_status" == "healthy" ]] || { echo "API 容器健康状态未就绪 (当前: ${api_status:-unknown})" >&2; failed=1; }
  fi

  local worker_id worker_status
  worker_id="$(compose ps -q worker || true)"
  [[ -n "$worker_id" ]] || { echo "Worker 未运行" >&2; failed=1; }
  if [[ -n "$worker_id" ]]; then
    worker_status="$(docker inspect --format '{{.State.Health.Status}}' "$worker_id" 2>/dev/null || true)"
    [[ "$worker_status" == "healthy" ]] || { echo "Worker 健康状态未就绪 (当前: ${worker_status:-unknown})" >&2; failed=1; }
  fi

  local http_port
  http_port="$(sed -n 's/^JIMOTABLE_HTTP_PORT=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
  http_port="${http_port:-8080}"
  curl --fail --silent "http://127.0.0.1:${http_port}/actuator/health" \
    | jq -e '.status == "UP"' >/dev/null || { echo "API HTTP 健康检查失败" >&2; failed=1; }

  [[ -s "$OPERATOR_FILE" ]] || { echo "operator.json 不存在" >&2; failed=1; }
  if [[ -s "$OPERATOR_FILE" ]]; then
    left="$(operator_seconds_left || echo 0)"
    (( left >= 7 * 86400 )) || { echo "operator 凭证已过期或将在 7 天内过期" >&2; failed=1; }
    jq -r '.secret' "$OPERATOR_FILE" | compose exec -T api sh -c '
      IFS= read -r token
      printf "header = \"Authorization: Bearer %s\"\n" "$token" \
        | curl --fail --silent --config - http://127.0.0.1:8080/v1/session
    ' | jq -e '.operator == true' >/dev/null || { echo "operator 鉴权验收失败" >&2; failed=1; }
  fi
  (( failed == 0 )) || return 1
  echo "验收通过：数据库、API、Worker、健康检查和 operator 凭证均有效。"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}

backup() {
  ensure_initialized
  require_command jq
  local kind="${1:-regular}" was_api was_worker result=0 timestamp id tmp target image major
  [[ "$kind" == regular || "$kind" == upgrade ]] || die "备份类型只能是 regular 或 upgrade"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"; id="${kind}-${timestamp}"
  mkdir -p "$BACKUPS_DIR"; chmod 700 "$BACKUPS_DIR"
  docker volume inspect "${PROJECT_NAME}_postgres-data" >/dev/null 2>&1 \
    || die "PostgreSQL 数据卷不存在；请先运行 up"
  docker volume inspect "${PROJECT_NAME}_app-data" >/dev/null 2>&1 \
    || die "应用数据卷不存在；请先运行 up"
  tmp="$BACKUPS_DIR/.tmp-$id"; target="$BACKUPS_DIR/$id"
  [[ ! -e "$tmp" && ! -e "$target" ]] || die "备份 ID 冲突：$id"
  image="$(postgres_image)"
  compose up -d --wait postgres >/dev/null
  major="$(postgres_major)"
  local source_kb available_kb required_kb
  source_kb="$(docker run --rm \
    -v "${PROJECT_NAME}_postgres-data:/postgres:ro" \
    -v "${PROJECT_NAME}_app-data:/app:ro" "$image" \
    sh -c "du -sk /postgres /app | awk '{total += \$1} END {print total}'")"
  available_kb="$(df -Pk "$BACKUPS_DIR" | awk 'NR == 2 {print $4}')"
  required_kb=$((source_kb + source_kb / 5 + 102400))
  (( available_kb >= required_kb )) \
    || die "备份空间不足：至少需要 ${required_kb} KiB，可用 ${available_kb} KiB"
  mkdir -p "$tmp/config" "$tmp/secrets"
  was_api="$(compose ps --status running -q api || true)"
  was_worker="$(compose ps --status running -q worker || true)"
  resume_services() {
    [[ -z "$was_api" ]] || compose start api >/dev/null || true
    [[ -z "$was_worker" ]] || compose start worker >/dev/null || true
  }
  trap 'resume_services' EXIT
  compose stop api worker >/dev/null
  compose up -d --wait postgres >/dev/null
  if ! compose exec -T postgres sh -c '
      PGPASSWORD=$(cat /run/secrets/postgres_password)
      export PGPASSWORD
      pg_dump -h 127.0.0.1 -U jimotable_owner -d jimotable -Fc
    ' > "$tmp/database.dump"; then result=1; fi
  if (( result == 0 )); then
    docker run --rm -v "${PROJECT_NAME}_app-data:/data:ro" \
      "$image" tar -C /data -czf - . > "$tmp/app-data.tar.gz" || result=1
  fi
  if (( result == 0 )); then
    cp "$ENV_FILE" "$COMPOSE_FILE" "$tmp/config/"
    cp "$SECRETS_DIR"/* "$tmp/secrets/"
    [[ ! -f "$OPERATOR_FILE" ]] || cp "$OPERATOR_FILE" "$tmp/operator.json"
    chmod -R go-rwx "$tmp"
    jq -n --arg id "$id" --arg kind "$kind" --arg created "$timestamp" \
      --arg version "$(sed -n 's/^JIMOTABLE_VERSION=//p' "$ENV_FILE" | tail -1)" \
      --arg postgresImage "$image" --argjson postgresMajor "$major" \
      '{id:$id,kind:$kind,createdAt:$created,version:$version,
        postgresImage:$postgresImage,postgresMajor:$postgresMajor}' > "$tmp/manifest.json"
    (cd "$tmp" && find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort \
      | while IFS= read -r file; do sha256_file "$file"; done > SHA256SUMS)
    mv "$tmp" "$target"
  else
    rm -rf "$tmp"
    resume_services
    trap - EXIT
    echo "错误：备份失败；服务已恢复到原运行状态" >&2
    return 1
  fi
  if [[ "$kind" == regular ]]; then
    local backups=() remove_count index backup_path
    while IFS= read -r backup_path; do backups+=("$backup_path"); done \
      < <(find "$BACKUPS_DIR" -mindepth 1 -maxdepth 1 -type d -name 'regular-*' | LC_ALL=C sort)
    remove_count=$((${#backups[@]} - 7))
    if (( remove_count > 0 )); then
      for ((index=0; index<remove_count; index++)); do rm -rf "${backups[$index]}"; done
    fi
  fi
  resume_services
  trap - EXIT
  echo "$id"
}

restore() {
  local id="${1:-}" confirmation="${2:-}" source image backup_major current_major
  [[ -n "$id" && "$confirmation" == "--yes" ]] || die "用法：$0 restore <id> --yes"
  ensure_initialized; source="$BACKUPS_DIR/$id"
  [[ -d "$source" ]] || die "备份不存在：$id"
  (cd "$source" && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi)
  require_command jq
  backup_major="$(jq -er '.postgresMajor | numbers' "$source/manifest.json")" \
    || die "备份未记录 PostgreSQL 大版本；请使用对应旧版本工具恢复，或单独迁移"
  image="$(postgres_image)"
  compose up -d --wait postgres >/dev/null
  current_major="$(postgres_major)"
  [[ "$backup_major" == "$current_major" ]] \
    || die "备份为 PostgreSQL $backup_major，当前为 $current_major；restore 不执行数据库大版本迁移"
  compose stop api worker >/dev/null || true
  compose exec -T postgres dropdb --force -U jimotable_owner jimotable
  compose exec -T postgres createdb -U jimotable_owner -O jimotable_owner jimotable
  compose exec -T postgres pg_restore -U jimotable_owner -d jimotable \
    --no-owner --exit-on-error < "$source/database.dump"
  docker run --rm -v "${PROJECT_NAME}_app-data:/data" -v "$source:/backup:ro" \
    "$image" sh -c 'find /data -mindepth 1 -delete && tar -C /data -xzf /backup/app-data.tar.gz'
  local current_proj="${COMPOSE_PROJECT_NAME:-}"
  if [[ -z "$current_proj" && -f "$ENV_FILE" ]]; then
    current_proj="$(sed -n 's/^COMPOSE_PROJECT_NAME=//p' "$ENV_FILE" | tail -1 | tr -d '\r\n')"
  fi
  cp "$source/config/.env" "$ENV_FILE"
  if [[ -n "$current_proj" ]]; then
    sed -i.bak '/^COMPOSE_PROJECT_NAME=/d' "$ENV_FILE"
    echo "COMPOSE_PROJECT_NAME=$current_proj" >> "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  fi
  find "$SECRETS_DIR" -mindepth 1 -maxdepth 1 -type f -delete
  cp "$source/secrets"/* "$SECRETS_DIR/"
  if [[ -f "$source/operator.json" ]]; then
    cp "$source/operator.json" "$OPERATOR_FILE"
  else
    rm -f "$OPERATOR_FILE"
  fi
  rm -f "$OPERATOR_FILE.previous"
  chmod 700 "$SECRETS_DIR"; chmod 600 "$ENV_FILE" "$SECRETS_DIR"/*
  [[ ! -f "$OPERATOR_FILE" ]] || chmod 600 "$OPERATOR_FILE"
  compose exec -T postgres sh -c '
    owner_password=$(cat /run/secrets/postgres_password)
    printf "ALTER ROLE jimotable_owner PASSWORD \$jimotable\$%s\$jimotable\$;\n" "$owner_password" \
      | psql -v ON_ERROR_STOP=1 -U jimotable_owner -d jimotable
  '
  run_db_init
  compose up -d --wait api worker
  verify
  echo "恢复完成：$id"
}

version_lt() {
  local a="${1#v}" b="${2#v}" i av bv a_pre b_pre max_parts
  IFS=. read -r -a aa <<< "${a%%-*}"; IFS=. read -r -a bb <<< "${b%%-*}"
  for i in 0 1 2; do av="${aa[$i]:-0}"; bv="${bb[$i]:-0}"; (( av < bv )) && return 0; (( av > bv )) && return 1; done

  a_pre=""; b_pre=""
  [[ "$a" != *-* ]] || a_pre="${a#*-}"
  [[ "$b" != *-* ]] || b_pre="${b#*-}"
  [[ -n "$a_pre" ]] || { [[ -n "$b_pre" ]] && return 1; return 1; }
  [[ -n "$b_pre" ]] || return 0

  IFS=. read -r -a aa <<< "$a_pre"; IFS=. read -r -a bb <<< "$b_pre"
  max_parts=${#aa[@]}; (( ${#bb[@]} > max_parts )) && max_parts=${#bb[@]}
  for ((i=0; i<max_parts; i++)); do
    [[ -n "${aa[$i]+set}" ]] || return 0
    [[ -n "${bb[$i]+set}" ]] || return 1
    av="${aa[$i]}"; bv="${bb[$i]}"
    [[ "$av" == "$bv" ]] && continue
    if [[ "$av" =~ ^[0-9]+$ && "$bv" =~ ^[0-9]+$ ]]; then
      (( 10#$av < 10#$bv )) && return 0
      return 1
    fi
    [[ "$av" =~ ^[0-9]+$ ]] && return 0
    [[ "$bv" =~ ^[0-9]+$ ]] && return 1
    [[ "$av" < "$bv" ]] && return 0
    return 1
  done
  return 1
}

check_upgrade_edition() {
  local target_version="$1" image full_image edition count
  image="$(sed -n 's/^JIMOTABLE_IMAGE=//p' "$ENV_FILE" | tail -1)"
  full_image="${image:-ghcr.io/jimotable/jimotable}:$target_version"
  docker image inspect "$full_image" >/dev/null 2>&1 || docker pull "$full_image" >/dev/null
  edition="$(docker image inspect "$full_image" --format '{{index .Config.Labels "com.jimotable.edition"}}')"
  if [[ "$edition" == free ]]; then
    count="$(compose exec -T postgres psql -U jimotable_owner -d jimotable -Atc 'SELECT count(*) FROM jimo_control.tenants')"
    [[ "$count" =~ ^[0-9]+$ && "$count" -le 1 ]] \
      || die "FREE_EXISTING_TENANTS_EXCEEDED: Free supports one tenant including disabled tenants. Keep the old image and migrate explicitly; no data or configuration was changed."
  fi
}

upgrade() {
  local version="${1:-}" current backup_id
  [[ "$version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
    || die "版本格式无效：$version"
  version="${version#v}"; ensure_initialized
  current="$(sed -n 's/^JIMOTABLE_VERSION=//p' "$ENV_FILE" | tail -1)"
  version_lt "$version" "$current" && die "不支持直接降级；请恢复升级前备份及旧镜像"
  [[ "$version" != "$current" ]] || die "已是版本 $version"
  check_upgrade_edition "$version"
  backup_id="$(backup upgrade)"
  sed -i.bak "s/^JIMOTABLE_VERSION=.*/JIMOTABLE_VERSION=$version/" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  if ! pull_or_build || ! run_db_init \
      || ! compose up -d --wait api worker || ! verify; then
    echo "升级失败。升级前备份：$backup_id" >&2
    echo "回滚：先将版本改回 $current，再运行 $0 restore $backup_id --yes" >&2
    return 1
  fi
  echo "已升级到 $version；迁移备份：$backup_id"
}

usage() {
  echo "用法：$0 {init|up|down|status|logs|bootstrap|operator-show --yes|operator-rotate|verify|backup|restore <id> --yes|upgrade <version>}"
}

main() {
  require_command docker
  local command="${1:-help}"
  case "$command" in
    init) init ;;
    up) up ;;
    down) down ;;
    status) require_command jq; status ;;
    logs) ensure_initialized; shift; compose logs -f --tail=200 "$@" ;;
    bootstrap) bootstrap ;;
    operator-show) operator_show "${2:-}" ;;
    operator-rotate) operator_rotate ;;
    verify) verify ;;
    backup) backup regular ;;
    restore) restore "${2:-}" "${3:-}" ;;
    upgrade) upgrade "${2:-}" ;;
    help|-h|--help) usage ;;
    *) usage; exit 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
