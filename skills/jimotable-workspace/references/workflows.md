# Workspace Agent API workflows

Use the live `GET /openapi.json` response as the authoritative contract. The examples below describe the stable workflow and common request shapes; a deployed version may expose fewer operations according to token capabilities or feature flags.

All paths in this reference are relative to `/agent-api/v1/workspace` and are intended for `scripts/workspace-api.sh`.

## Discover and select targets

```bash
bash scripts/workspace-api.sh request GET /quota
bash scripts/workspace-api.sh request GET /bases
bash scripts/workspace-api.sh request GET /bases/{baseId}/schema
```

Resolve resources by human-readable name only during discovery. Persist and use the returned `baseId`, `tableId`, and `fieldId` values for subsequent calls. Before creating a new resource, confirm an equivalent resource does not already exist unless duplication is explicitly intended.

## Create a Base

```bash
bash scripts/workspace-api.sh request POST /bases \
  '{"displayName":"Customer Operations"}' \
  'customer-operations-base-v1'
```

Save `baseId`, `jobId`, and `status`. If the result is `PENDING`, poll `/jobs/{jobId}`. Do not guess a Base ID from its display name.

## Create a table with initial fields

Prefer one `create_table` request with its initial fields; the current contract permits up to 30 initial fields.

```json
{
  "displayName": "Customers",
  "fields": [
    {
      "displayName": "Name",
      "type": "short_text",
      "config": { "maxLength": 255 },
      "nullable": false
    },
    {
      "displayName": "Priority",
      "type": "single_select",
      "config": {
        "options": [
          { "key": "high", "label": "High" },
          { "key": "normal", "label": "Normal" }
        ]
      },
      "nullable": false
    }
  ]
}
```

Send it to `/bases/{baseId}/tables` with a stable idempotency key. Field types and required `config` shapes must come from `components.schemas.FieldInput` in the live OpenAPI.

If a table-with-fields request returns `PENDING`:

1. Poll its current `jobId` until `SUCCEEDED`.
2. Replay the exact original `create_table` body with the exact original idempotency key.
3. Repeat only while the response identifies additional pending schema work.
4. Stop on `FAILED`, `CANCELLED`, or `MANUAL_INTERVENTION`, and report `errorCode`.

This replay behavior lets the server continue fields that were not yet submitted; changing the body under the same key causes an idempotency conflict.

## Add one field

POST a `FieldInput` body to `/bases/{baseId}/tables/{tableId}/fields` with an idempotency key. Read the schema again after success and capture the returned `fieldId` rather than relying on array position.

Relation fields require stable IDs in their config:

```json
{
  "displayName": "Customer",
  "type": "relation",
  "nullable": false,
  "config": {
    "cardinality": "SINGLE",
    "targetTableId": "<targetTableId>",
    "labelFieldId": "<targetLabelFieldId>",
    "onDelete": "RESTRICT"
  }
}
```

Create the target table and label field first so these IDs exist.

## Poll schema jobs

```bash
bash scripts/workspace-api.sh request GET /jobs/{jobId}
```

Use bounded polling. A normal interactive workflow should report progress instead of waiting silently. Treat `SUCCEEDED` as success. Treat `FAILED`, `CANCELLED`, and `MANUAL_INTERVENTION` as terminal and surface the response. If the status remains nonterminal beyond the task's reasonable deadline, stop and report the last status; do not create replacement schema operations speculatively.

## Create records

Read the active schema immediately before constructing records. Each record is an object keyed by stable `fieldId`, not field display name. Submit 1–100 records per request:

```json
{
  "records": [
    {
      "<nameFieldId>": "Acme",
      "<priorityFieldId>": "high"
    },
    {
      "<nameFieldId>": "Globex",
      "<priorityFieldId>": "normal"
    }
  ]
}
```

POST to `/bases/{baseId}/tables/{tableId}/records/batch-create` with a stable idempotency key. Preserve the exact body and key until the response is known. Verify returned record IDs and values with a query.

For relation values, use a target record ID string for `SINGLE` and an array of target record IDs for `MULTIPLE`.

## Query records

```bash
bash scripts/workspace-api.sh request POST \
  '/bases/{baseId}/tables/{tableId}/records/query?limit=50'
```

Follow `nextCursor` until it is null only when the task needs all results. URL-encode cursor values before adding them to the query string. Keep `mappingVersion` with exported or transformed data when it is needed to detect schema mapping changes.

## Failure handling

- `401`: token is absent, invalid, expired, rotated, or revoked. Stop and request a valid AGENT_USER credential.
- `403`: token lacks the required capability or access scope. Compare the requested operation with the live OpenAPI.
- `409`: usually an idempotency-key/body mismatch or revision conflict. Do not invent a new key until the original operation's state is understood.
- `422`: request shape, field config, field value, or resource state is invalid. Re-read OpenAPI and active schema.
- `429`: inspect the error code to distinguish per-token rate/concurrency limiting from tenant/user quota exhaustion. Apply a bounded backoff only to a retryable rate limit; quota exhaustion requires a scope or quota decision.
