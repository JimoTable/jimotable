# Base Agent API Reference

## Endpoint Structure

The Base Agent API is published on an isolated path:
`https://<domain>/agent-api/v1/{publicBaseId}`

### 1. GET `/schema`
Returns all tables, visible fields, and semantic identifiers for this Base.

### 2. GET `/openapi.json`
Returns a standalone OpenAPI 3.0.3 specification tailored specifically to this Base and your token permissions. Can be directly imported into Dify, Postman, or Swagger UI.

### 3. POST `/tables/{table}/records/query`
Query records with filtering, sorting, and pagination.

Request body:
```json
{
  "filters": [
    {
      "field": "Status",
      "operator": "EQUALS",
      "value": "Active"
    }
  ],
  "sorts": [
    {
      "field": "CreatedAt",
      "direction": "DESC"
    }
  ],
  "limit": 50,
  "cursor": null
}
```

### 4. POST `/tables/{table}/records`
Create a new record. Always requires an `idempotencyKey`.

Request body:
```json
{
  "idempotencyKey": "unique-task-uuid-or-timestamp",
  "fields": {
    "CustomerName": "Acme Inc",
    "Priority": "High",
    "ContactEmail": "alex@acme.com"
  }
}
```

### 5. PATCH `/tables/{table}/records/{recordId}`
Partially update an existing record. Requires optimistic concurrency `version` to prevent race conditions.

Request body:
```json
{
  "idempotencyKey": "unique-update-key",
  "version": 1,
  "fields": {
    "Status": "Closed"
  }
}
```

### 6. DELETE `/tables/{table}/records/{recordId}`
Soft-deletes the record (moves it to the 7-day trash bin).
