# JimoTable Architecture & Engineering Overview

## 1. The Core Design Principles

JimoTable is designed from the ground up for the AI Agent era, solving the mismatch between traditional databases and agentic workflows.

### 1.1 Base-per-schema Isolation
Many modern no-code platforms store all dynamic tables inside a single huge `records` table with a `JSONB` or EAV (Entity-Attribute-Value) column. While easy to implement initially, this pattern causes severe bottlenecks:
- Inability to utilize standard PostgreSQL B-Tree indexes and statistics.
- Schema migrations become heavy JSON transformations.
- Dangerous lock contention during concurrent AI writes.

**JimoTable maps every Base to its own PostgreSQL Schema**:
- Tables in Base A are physical PostgreSQL tables inside `schema_base_a`.
- Indexes, primary keys, and data types (DECIMAL, TIMESTAMP, TEXT) are physical PostgreSQL native primitives.
- Schema operations are atomic and asynchronous, managed by a dedicated Worker process with live progress tracking.

---

## 2. Component Layout

```
                        ┌──────────────────────────────┐
                        │   AI Agents (Dify / Cursor)  │
                        └──────────────┬───────────────┘
                                       │ HTTP / OpenAPI
                                       ▼
    ┌──────────────────────────────────────────────────────────────────┐
    │                      JimoTable API Container                     │
    │  - Gateway & Auth (Bearer Token / Agent Token / SSO)             │
    │  - Workspace Agent API (/agent-api/v1/workspace)                │
    │  - Base Agent API Publication (/agent-api/v1/{publicBaseId})     │
    │  - Built-in High-Density Vue Web Console (Static Hosting)        │
    └─────────────────┬──────────────────────────────┬─────────────────┘
                      │ JDBC Connection              │ Task Outbox
                      ▼                              ▼
    ┌──────────────────────────────────┐   ┌───────────────────────────┐
    │          PostgreSQL 18           │   │  JimoTable Worker Container│
    │  - Public Catalog & RBAC         │   │  - Async Schema Migration │
    │  - Base-per-schema Business Data │   │  - Large Excel Imports    │
    │  - Change Sets & Audit Ledger    │   │  - Async CSV Export Jobs  │
    └──────────────────────────────────┘   └───────────────────────────┘
```

---

## 3. Human-in-the-loop: Relational Drawers

The fundamental UX differentiation of JimoTable is the **Relational Detail Drawer**:
1. When an AI Agent populates records into a relational structure (e.g. `Customers` 1:N `Activities`), the relationship is stored as a validated pointer.
2. When a human business user browses the `Customers` grid and clicks on a company row, a detail drawer slides out from the right margin without causing page reload or navigation loss.
3. The drawer renders all historical sub-records, attachment previews, and allows inline status edits or follow-up reassignments.
