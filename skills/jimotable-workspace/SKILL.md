---
name: jimotable-workspace
description: Use a deployed jimoTable Workspace Agent API to create Bases and schema, inspect quota, and query or write records with an AGENT_USER credential. Use for remote dev, staging, or production-style HTTP environments; do not use for local Native Tool API pipelines or Base-scoped Agent API publications.
metadata:
  version: 1.0.0
  category: integration
---

# jimoTable Workspace

Operate a deployed jimoTable environment through `/agent-api/v1/workspace`. This skill is environment-independent: it must not depend on the repository's Demo state, `/tmp/jmt-base.json`, database access, internal JWT keys, AI connections, pipelines, or execution-bound Tool Tokens.

Requires Bash, `curl`, `jq`, a reachable jimoTable HTTP endpoint, and an `AGENT_USER` token.

## Connection contract

Require these environment variables:

- `JIMOTABLE_API_URL`: deployment origin, for example `https://jimo-dev.example.com`; a trailing slash is allowed.
- `JIMOTABLE_AGENT_USER_TOKEN`: an `AGENT_USER` Bearer secret issued for this environment. Never substitute a Base Agent API Token or Native Tool Token.
- `JIMOTABLE_HTTP_TIMEOUT_SECONDS`: optional positive integer; defaults to `30`.

If either required variable is unavailable, stop before making API calls and ask the user to provide or configure it. Never search shell history, logs, source files, or unrelated credential stores for a missing secret. Never print the token.

Resolve [scripts/workspace-api.sh](scripts/workspace-api.sh) relative to this file. Start each new environment session with:

```bash
bash scripts/workspace-api.sh check
```

The helper keeps the token in the Authorization header, rejects absolute request paths, validates JSON bodies, and reports non-2xx responses without hiding their error body.

## Operating workflow

1. Run `check` and treat the returned, capability-shaped OpenAPI document as the source of truth for the current token and deployment.
2. Inspect before mutating: list Bases, read the target Base schema, and check quota when relevant.
3. Use stable Base, Table, and Field IDs from API responses. Display names are for people and are not record keys.
4. For every schema or record write, choose a unique stable `Idempotency-Key`. If a request times out or is retried, reuse both the exact key and exact JSON body. Never reuse that key for different content.
5. Handle schema operations by status. Poll a returned `jobId` while status is `PENDING`; stop on a documented terminal failure. A partially completed `create_table` must be retried with the same key and body after its current job succeeds so the service can continue remaining fields.
6. After a mutation, read the schema or records back and verify IDs, values, counts, and mapping revision as appropriate.

Read [references/workflows.md](references/workflows.md) before creating schema or records. It contains request shapes, job handling, and examples. For read-only discovery, the live OpenAPI plus the helper is sufficient.

## Request helper

Paths passed to the helper are relative to `/agent-api/v1/workspace`:

```bash
# Fetch the complete capability-shaped contract
bash scripts/workspace-api.sh openapi

# Read
bash scripts/workspace-api.sh request GET /bases
bash scripts/workspace-api.sh request GET /bases/{baseId}/schema

# Write: METHOD PATH JSON IDEMPOTENCY_KEY
bash scripts/workspace-api.sh request POST /bases \
  '{"displayName":"CRM"}' 'crm-base-v1'
```

JSON may be passed inline or as `@/absolute/path/request.json`. Keep reusable mutation bodies in a task-scoped file when that reduces accidental differences during retries.

## Authorization and safety boundaries

- `BUILDER` tokens can manage Base/schema operations; `DATA` tokens can discover schema and read/write records; `COMBINED` tokens cover both. The live OpenAPI omits operations the token cannot perform.
- Do not use the management endpoint `/v1/agent-users/tokens` unless the user explicitly asks to issue or revoke credentials. This skill consumes an already-issued token.
- A request to inspect, explain, or diagnose does not authorize schema or record mutations.
- Do not retry `401` or `403` automatically. Report whether the likely cause is invalid/expired credentials, missing capability, or Base scope.
- For `409`, preserve the original key/body and inspect the error code before deciding whether a replay is safe.
- For `429`, distinguish rate limiting from quota exhaustion using the response error code; do not loop indefinitely.
- Do not add `curl -k` or otherwise disable TLS verification.
