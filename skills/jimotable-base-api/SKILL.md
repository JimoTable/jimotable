---
name: jimotable-base-api
description: Query and mutate records in an independently published JimoTable Base using its Base Agent API (/agent-api/v1/{publicBaseId}). Scoped, table-level permissions with semantic OpenAPI.
metadata:
  version: 1.0.0
  category: integration
---

# JimoTable Base Agent API Skill

Connect an AI Agent to an independently published JimoTable Base.

Unlike the Workspace API (which requires an admin `AGENT_USER` credential to manage tables across the entire workspace), the **Base Agent API** is scoped to a single published Base (e.g. `https://<domain>/agent-api/v1/bp_xxxxxx`). It provides:
- Scoped Bearer token (`jmt_cred_...`) with strict table-level read/write/delete permissions.
- Semantic paths and field names (e.g. `/tables/customers`, `/tables/activities`).
- Zero-token OpenAPI specification (`/openapi.json`).

## Connection contract

Require these environment variables:

- `JIMOTABLE_BASE_URL`: The Base endpoint published from the UI, e.g. `http://127.0.0.1:8080/agent-api/v1/bp_xxxxxx`.
- `JIMOTABLE_BASE_TOKEN`: The scoped token issued for this Base, e.g. `jmt_cred_xxxxxx`.

## CLI Usage

The bundled Python script `scripts/base-api.py` uses only Python 3 standard libraries:

```bash
# 1. Fetch schema and table structure
python3 scripts/base-api.py schema

# 2. Query records from a table
python3 scripts/base-api.py query --table Customers --limit 10

# 3. Create a record with automatic idempotency key
python3 scripts/base-api.py create --table Customers --json '{"CustomerName":"Globex Corp","Intent":"A"}'

# 4. Update a record (optimistic locking with version)
python3 scripts/base-api.py update --table Customers --id <recordId> --version 1 --json '{"Intent":"B"}'
```

See [references/api-specs.md](references/api-specs.md) for full parameter specifications and filtering syntax.
