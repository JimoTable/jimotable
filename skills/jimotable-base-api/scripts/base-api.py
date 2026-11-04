#!/usr/bin/env python3
"""
JimoTable Base Agent API CLI Helper
Zero-dependency Python 3 client for interacting with a published JimoTable Base.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid


def get_env_or_die(var_name: str) -> str:
    val = os.environ.get(var_name, "").strip()
    if not val:
        sys.stderr.write(f"Error: Environment variable {var_name} is required.\n")
        sys.exit(2)
    return val


def request(method: str, base_url: str, path: str, token: str, body: dict = None) -> dict:
    url = f"{base_url.rstrip('/')}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            resp_body = resp.read().decode("utf-8")
            if not resp_body:
                return {}
            return json.loads(resp_body)
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="replace")
        sys.stderr.write(f"HTTP {e.code} Error for {method} {url}:\n{err_msg}\n")
        sys.exit(1)
    except Exception as e:
        sys.stderr.write(f"Network error: {e}\n")
        sys.exit(1)


def cmd_schema(base_url: str, token: str, args):
    res = request("GET", base_url, "schema", token)
    print(json.dumps(res, indent=2, ensure_ascii=False))


def cmd_query(base_url: str, token: str, args):
    payload = {
        "filters": json.loads(args.filters) if args.filters else [],
        "sorts": json.loads(args.sorts) if args.sorts else [],
        "limit": args.limit,
    }
    path = f"tables/{args.table}/records/query"
    res = request("POST", base_url, path, token, payload)
    print(json.dumps(res, indent=2, ensure_ascii=False))


def cmd_create(base_url: str, token: str, args):
    fields = json.loads(args.json)
    idempotency_key = args.idempotency_key or f"cli-{int(time.time())}-{uuid.uuid4().hex[:8]}"
    payload = {
        "idempotencyKey": idempotency_key,
        "fields": fields,
    }
    path = f"tables/{args.table}/records"
    res = request("POST", base_url, path, token, payload)
    print(json.dumps(res, indent=2, ensure_ascii=False))


def cmd_update(base_url: str, token: str, args):
    fields = json.loads(args.json)
    idempotency_key = args.idempotency_key or f"cli-upd-{int(time.time())}-{uuid.uuid4().hex[:8]}"
    payload = {
        "idempotencyKey": idempotency_key,
        "version": args.version,
        "fields": fields,
    }
    path = f"tables/{args.table}/records/{args.id}"
    res = request("PATCH", base_url, path, token, payload)
    print(json.dumps(res, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="JimoTable Base Agent API CLI")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # schema
    subparsers.add_parser("schema", help="Fetch schema and table metadata")

    # query
    p_query = subparsers.add_parser("query", help="Query records from a table")
    p_query.add_argument("--table", required=True, help="Table name or API identifier")
    p_query.add_argument("--limit", type=int, default=50, help="Page limit")
    p_query.add_argument("--filters", help="JSON filter array")
    p_query.add_argument("--sorts", help="JSON sorts array")

    # create
    p_create = subparsers.add_parser("create", help="Create a record in a table")
    p_create.add_argument("--table", required=True, help="Table name or API identifier")
    p_create.add_argument("--json", required=True, help="JSON dictionary of fields")
    p_create.add_argument("--idempotency-key", help="Optional unique idempotency key")

    # update
    p_update = subparsers.add_parser("update", help="Update a record")
    p_update.add_argument("--table", required=True, help="Table name or API identifier")
    p_update.add_argument("--id", required=True, help="Record ID")
    p_update.add_argument("--version", type=int, required=True, help="Current record version")
    p_update.add_argument("--json", required=True, help="JSON dictionary of modified fields")
    p_update.add_argument("--idempotency-key", help="Optional unique idempotency key")

    args = parser.parse_args()

    base_url = get_env_or_die("JIMOTABLE_BASE_URL")
    token = get_env_or_die("JIMOTABLE_BASE_TOKEN")

    if args.subcommand == "schema":
        cmd_schema(base_url, token, args)
    elif args.subcommand == "query":
        cmd_query(base_url, token, args)
    elif args.subcommand == "create":
        cmd_create(base_url, token, args)
    elif args.subcommand == "update":
        cmd_update(base_url, token, args)


if __name__ == "__main__":
    main()
