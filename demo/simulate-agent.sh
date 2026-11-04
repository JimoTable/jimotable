#!/usr/bin/env bash
set -euo pipefail
cat <<'DEMO'
jimoTable — CRM workflow simulation / CRM 流程模拟

This is printed example output only. No API calls, model calls, database writes
or notifications are performed. The web UI will not contain these sample records.
仅打印虚构示例，不调用 API 或模型、不写入数据、不发送通知；网页不会产生演示记录。

1. Example input: a customer asks about deploying 50 seats.
2. Example query: look up a customer by company name.
3. Example mutation: link a follow-up activity to the customer.
4. Example view: display pending follow-ups for a sales representative.

To perform real operations, create your own schema and use the published Agent
API with a scoped credential. See skills/jimotable-workspace/SKILL.md.
DEMO
