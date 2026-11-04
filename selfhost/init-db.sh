#!/bin/sh
set -eu

read_file() {
  file="$1"
  [ -r "$file" ] || { echo "secret file is not readable: $file" >&2; exit 78; }
  tr -d '\r\n' < "$file"
}

PGPASSWORD="$(read_file "$POSTGRES_PASSWORD_FILE")"
export PGPASSWORD
runtime_password="$(read_file "$JIMOTABLE_RUNTIME_DB_PASSWORD_FILE")"
worker_password="$(read_file "$JIMOTABLE_WORKER_DB_PASSWORD_FILE")"

psql -v ON_ERROR_STOP=1 \
  -v runtime_user="$JIMOTABLE_RUNTIME_DB_USER" \
  -v runtime_password="$runtime_password" \
  -v worker_user="$JIMOTABLE_WORKER_DB_USER" \
  -v worker_password="$worker_password" <<'SQL'
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jimo_runtime_dml') THEN
    CREATE ROLE jimo_runtime_dml NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jimo_auth_runtime') THEN
    CREATE ROLE jimo_auth_runtime NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jimo_schema_worker') THEN
    CREATE ROLE jimo_schema_worker NOLOGIN NOINHERIT;
  END IF;
END
$roles$;

SELECT format('CREATE ROLE %I LOGIN NOINHERIT', :'runtime_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'runtime_user') \gexec
SELECT format('CREATE ROLE %I LOGIN NOINHERIT', :'worker_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'worker_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'runtime_user', :'runtime_password') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'worker_user', :'worker_password') \gexec
SELECT format('GRANT jimo_runtime_dml, jimo_auth_runtime TO %I', :'runtime_user') \gexec
SELECT format('REVOKE jimo_schema_worker FROM %I', :'runtime_user') \gexec
SELECT format('GRANT jimo_schema_worker, jimo_runtime_dml TO %I', :'worker_user') \gexec
SELECT format('REVOKE jimo_auth_runtime FROM %I', :'worker_user') \gexec
SQL

echo "Database roles are ready."
