#!/bin/sh
set -eu

read_secret() {
  variable="$1"
  file_variable="${variable}_FILE"
  eval "secret_file=\${$file_variable:-}"
  if [ -n "$secret_file" ]; then
    if [ ! -r "$secret_file" ]; then
      echo "required secret file is not readable: $secret_file" >&2
      exit 78
    fi
    value=$(tr -d '\r\n' < "$secret_file")
    if [ -z "$value" ]; then
      echo "required secret file is empty: $secret_file" >&2
      exit 78
    fi
    export "$variable=$value"
    unset "$file_variable"
  fi
}

run_app() {
  jar="$1"
  if [ "$(id -u)" = "0" ]; then
    if ! command -v setpriv >/dev/null 2>&1; then
      echo "required tool setpriv is not available for privilege dropping" >&2
      exit 1
    fi
    import_dir="${JIMOTABLE_IMPORT_LOCAL_PATH:-/tmp/jimotable-artifacts}"
    mkdir -p "$import_dir"
    chown 10001:10001 "$import_dir"
    chmod 700 "$import_dir"

    if [ "${JIMOTABLE_ATTACHMENT_STORAGE_TYPE:-local}" = "local" ]; then
      att_dir="${JIMOTABLE_ATTACHMENT_STORAGE_LOCAL_ROOT:-/tmp/jimotable-attachments}"
      mkdir -p "$att_dir"
      chown 10001:10001 "$att_dir"
      chmod 700 "$att_dir"
    fi


    # shellcheck disable=SC2086
    exec setpriv --reuid=10001 --regid=10001 --init-groups --no-new-privs java ${JAVA_OPTS:-} -jar "$jar"
  else
    # shellcheck disable=SC2086
    exec java ${JAVA_OPTS:-} -jar "$jar"
  fi
}

role="${1:-api}"
case "$role" in
  api)
    read_secret JIMOTABLE_DB_PASSWORD
    read_secret JIMOTABLE_MIGRATION_DB_PASSWORD
    read_secret JIMOTABLE_CREDENTIAL_DIGEST_KEY
    read_secret JIMOTABLE_INTERNAL_JWT_KEY
    read_secret JIMOTABLE_BOOTSTRAP_SECRET
    read_secret JIMOTABLE_AI_CREDENTIAL_MASTER_KEY
    run_app /opt/jimotable/api.jar
    ;;
  worker)
    read_secret JIMOTABLE_DB_PASSWORD
    read_secret JIMOTABLE_CURSOR_KEY
    read_secret JIMOTABLE_AI_CREDENTIAL_MASTER_KEY
    run_app /opt/jimotable/worker.jar
    ;;
  *)
    echo "usage: entrypoint.sh api|worker" >&2
    exit 64
    ;;
esac
