---
name: vapor-agent-memory
description: "Search Vapor's local indexed agent memory for the current session, including conversation turns and indexed tool/reasoning history."
---

# Vapor Agent Memory Search

Use this skill when you need to recall prior decisions, errors, implementation details, tool results, or reasoning from the current indexed agent session.

Vapor exposes a local HTTP API on `http://127.0.0.1:8766`. Requests require `VAPOR_API_TOKEN` as a Bearer token.

## Workflow

1. Check index status before searching.
2. Search only if `can_search` is `true`.
3. If `can_search` is `false`, tell the user which Vapor UI action is needed.
4. Use context expansion before relying on a result.

## Authentication

```bash
TOKEN="$VAPOR_API_TOKEN"
BASE="${VAPOR_API_URL:-http://127.0.0.1:8766}"
```

## Check Current Session

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/current-session?cwd=$(python3 -c 'import os,urllib.parse; print(urllib.parse.quote(os.getcwd()))')" \
  | python3 -m json.tool
```

## Check Index Status

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/index/status?session_id=ses_abc123" \
  | python3 -m json.tool
```

Status values:

- `ready`: search is ready.
- `dirty`: search is usable but session has newer data; ask the user to click **Update Search** in Vapor.
- `partial`: search is usable but incomplete; ask the user to click **Update Search** if recall matters.
- `repair_needed`: search is unavailable; ask the user to click **Repair Search** in Vapor.
- `missing`: session is not imported; ask the user to click **Import & Index** in Vapor.
- `indexing`: indexing is running; try again shortly.

## Search Agent Memory

```bash
QUERY="dictation on local device vs cloud based"
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/search?q=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")&limit=10" \
  | python3 -m json.tool
```

Explicit session:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/sessions/ses_abc123/search?q=sqlite%20vec%20filtering&limit=10" \
  | python3 -m json.tool
```

## Interpret Results

The score is cosine distance. Lower is better.

- `0.0` is closest.
- `< 0.30` is typically strong.
- `< 0.60` is related.
- Larger values are weaker.

## Expand Context

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/sessions/ses_abc123/context?q=sqlite%20vec%20filtering&context_turns=2" \
  | python3 -m json.tool
```

Use context expansion before making claims based on a search result.

## Rules

- Prefer current-session search unless the user asks for cross-session recall.
- Always check status first if search quality matters.
- If `can_search` is false, do not claim nothing was found; report the required Vapor action.
- Do not trigger indexing from the API unless the user explicitly asks and the endpoint supports it.
