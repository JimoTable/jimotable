# Free single-host installation

This release supports Linux amd64 (x86-64). ARM64 is not qualified for this release.

Use a Linux host with Docker Engine 24+, Docker Compose v2, curl, jq and OpenSSL.
Suggested minimum: 2 vCPU, 4 GiB RAM and 20 GiB available disk.

Verify `SHA256SUMS` with `sha256sum -c SHA256SUMS`, extract the archive, and enter
its directory. All paths below are relative to that directory.

```bash
./selfhost/jimotable.sh init
# Edit .env for your public URL and port before starting.
./quickstart.sh
./selfhost/jimotable.sh verify
./selfhost/jimotable.sh operator-show --yes
```

Open http://127.0.0.1:8080 by default. Use the generated operator credential to
connect. Repeating quickstart validates and reuses it. Interrupted bootstrap can
be retried without deleting its state, secrets or database volumes.

The API binds to loopback only. For public access, set JIMOTABLE_PUBLIC_BASE_URL
to your HTTPS origin in `.env` and configure a reverse proxy to the chosen local
HTTP port. PostgreSQL and Worker do not expose host ports.

Free defaults: 2 Bases per tenant, 20 tables per Base, 30 fields per table,
2,000,000 records per tenant, 100,000 per table, and 1 GiB attachments per tenant.
PostgreSQL defaults to postgres:18.6-alpine. Attachments/imports use local volumes.
The AI adapter is mock and external AI delivery is disabled. Real providers and
object storage require separate configuration and validation.

```bash
./selfhost/jimotable.sh status
./selfhost/jimotable.sh logs api
./selfhost/jimotable.sh logs worker
backup_id=$(./selfhost/jimotable.sh backup)
# Destructive: replaces data in this installation with the selected backup.
./selfhost/jimotable.sh restore "$backup_id" --yes
./selfhost/jimotable.sh verify
```

Backup pauses API and Worker, then resumes them. Preserve the entire backup,
including database, files, configuration, operator credential and secrets.
Copy backups securely to another host and rehearse restoration. The restore
command rejects PostgreSQL major-version mismatches; never attach a PG16/17 data
volume to PG18. Application upgrade does not upgrade PostgreSQL.

Keep `.env`, `selfhost/secrets/` and `selfhost/operator.json` private. Do not
regenerate secrets against existing data. Use `operator-rotate` to renew an
operator credential, followed by `verify`.

For a future application upgrade, run `./selfhost/jimotable.sh upgrade VERSION`
with an actually published version. It creates an upgrade backup first. If the
upgrade fails, restore the previous version setting in `.env` and restore the
corresponding upgrade backup. Direct database downgrade is not supported.

Installation failures must be investigated using status/logs; do not delete
volumes to repair them. This bundle does not promise zero-downtime backups,
multi-node high availability or fixed recovery objectives.

## Free edition boundary (0.2.1)

Each Free installation supports one business tenant, including disabled tenants. These are ceilings enforced by the image; environment variables cannot raise them. Operators may allocate or lower quotas within these ceilings.

Back up before upgrading. Existing multi-tenant databases require an explicit migration and cannot start with this Free image. The upgrade helper checks before changing the configured version. No tenants are automatically removed. Keep the previous image for recovery.
