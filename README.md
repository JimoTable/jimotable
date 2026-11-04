# jimoTable Free SelfHost

This release supports Linux amd64 (x86-64). ARM64 is not qualified for this release.

[English](README.md) | [简体中文](README.zh-CN.md)

A PostgreSQL-backed table application and Agent API with a web UI, relations, attachments and background jobs.

## Install

This directory contains the Free distribution, identical to the public repository at https://github.com/jimotable/jimotable. Download the install bundle from https://jimotable.jimo.studio/releases/ and verify its SHA256SUMS before extracting, or clone the repository and run the steps below. A live sandbox runs at https://app.jimotable.jimo.studio.

A Linux host needs Docker Engine 24+, Docker Compose v2, curl, jq and OpenSSL. Suggested minimum: 2 vCPU, 4 GiB RAM and 20 GiB available disk. Run:

```bash
./quickstart.sh
```

Or run the individual steps:

```bash
./selfhost/jimotable.sh init
./selfhost/jimotable.sh up
./selfhost/jimotable.sh bootstrap
./selfhost/jimotable.sh verify
```

The default URL is http://127.0.0.1:8080. Edit `.env` before starting to customize the port and public URL. Use `./selfhost/jimotable.sh operator-show --yes` to inspect the operator credential; do not share it.

The published image is `ghcr.io/jimotable/jimotable:0.2.1` and pulls anonymously. Candidate validation uses the designated image supplied by the maintainer; an old cached image does not validate a new release.

## Deployment defaults

- Single-host Docker Compose with `postgres:18.6-alpine`.
- Local persistent volumes for attachments and imports; S3/MinIO is not configured by default.
- The AI adapter defaults to `mock` and external AI delivery is disabled. Real providers require separate configuration and verification. Attachment, import and asynchronous schema jobs remain available.
- The API binds only to host loopback. Public access requires an HTTPS reverse proxy. PostgreSQL and Worker have no host ports.
- Backup and restore tooling is included; multi-node HA, zero-downtime backup and fixed RPO/RTO are not promised.

Edition limits are documented in [INSTALL.en-US.md](INSTALL.en-US.md) and may change between releases.

## Agent skills

Use [skills/jimotable-workspace/](skills/jimotable-workspace/) or [skills/jimotable-base-api/](skills/jimotable-base-api/) with your agent tool's local skill-loading mechanism and a dedicated credential.

Both skills are published in this repository under `skills/`; copy them into your agent tool's local skill directory. A remote `npx skills add` flow is not offered because that installation path has not been verified. Workspace agents use an `AGENT_USER` credential. Base agents use a published Base API and its scoped credential.

## Simulation

```bash
./demo/simulate-agent.sh
```

This script prints a fictional CRM workflow only. It makes no HTTP requests, calls no models, writes no database records and sends no notifications. It does not populate the web UI.

## Operations

```bash
./selfhost/jimotable.sh status
./selfhost/jimotable.sh logs
backup_id=$(./selfhost/jimotable.sh backup)
# Destructive: run only after confirming the intended restore target.
./selfhost/jimotable.sh restore "$backup_id" --yes
```

Backups pause API/Worker. Protect `.env`, `selfhost/secrets/`, `selfhost/operator.json` and backups, and copy backups to another host. See `INSTALL.en-US.md` in the release bundle for installation details.

## License

`LICENSE` is a custom **Community Free License**, not an OSI-approved open-source licence — which is why GitHub labels it "Other". In short:

- You may self-host and run the Free edition, including for internal business evaluation.
- You may not reverse-engineer, decompile or modify the proprietary core binaries.
- You may not remove copyright, trademark or attribution notices.
- Cloud and enterprise features are not part of this distribution and are neither described nor promised here.

See [LICENSE](LICENSE) for the binding text.

## Upgrading

Back up before upgrading. A database holding more tenants than the Free edition supports must be migrated first; the upgrade helper checks before changing the configured version and refuses rather than removing data. Keep the previous image for recovery.
