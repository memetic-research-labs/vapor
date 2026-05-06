# Agent Memory API

Vapor can index local agent sessions and expose them through a local authenticated HTTP API. Agents can use this API to search prior conversation history, implementation decisions, errors, and tool results from the current indexed session.

The API is local-first:

- Server: `http://127.0.0.1:8766`
- Auth: Bearer token via `VAPOR_API_TOKEN`
- Current source: OpenCode sessions from `~/.local/share/opencode/opencode.db`
- Vector store: `~/Library/Application Support/Vapor/vectors.db`
- Embedding model: MiniLM `all-MiniLM-L6-v2`

## User Workflow

1. Open Vapor.
2. Open the Context Tray and expand **Sessions**.
3. Open an agent session.
4. Use the session header action when needed:
   - **Import & Index** for a session that has not been indexed.
   - **Update Search** for a session with a usable but stale or partial index.
   - **Repair Search** for a session with imported data but no usable search vectors.
5. Agents can query the API once `can_search` is `true`.

## Search Index Statuses

| Status | Can Search | Meaning | User Action |
| --- | ---: | --- | --- |
| `ready` | Yes | Chunks and vectors are present and current. | None |
| `dirty` | Yes | Session has newer data than the last import. | Click **Update Search** for best recall. |
| `partial` | Yes | Some vectors are missing, but enough exist to search. | Search works; click **Update Search** if recall matters. |
| `repair_needed` | No | Imported content exists but no usable search vectors are available. | Click **Repair Search**. |
| `missing` | No | Session is not imported. | Click **Import & Index**. |
| `indexing` | Soon | Importing or indexing is in progress. | Wait and retry shortly. |

Agents should check index status before searching. If `can_search` is false, the agent should report the provided `message` to the user instead of claiming no results were found.

## Authentication

All API requests require a bearer token:

```bash
TOKEN="$VAPOR_API_TOKEN"
BASE="${VAPOR_API_URL:-http://127.0.0.1:8766}"
```

Vapor sets `VAPOR_API_TOKEN` for child processes it launches. If an agent is launched outside Vapor's environment, the user must provide or export the token.

## Endpoints

### Current Session

```http
GET /api/agent/current-session
```

Optional query parameters:

- `cwd`: current working directory used to infer the session.
- `source`: source adapter, currently `opencode`.

Example:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/current-session?cwd=$(python3 -c 'import os,urllib.parse; print(urllib.parse.quote(os.getcwd()))')" \
  | python3 -m json.tool
```

Response shape:

```json
{
  "source": "opencode",
  "session_id": "ses_...",
  "title": "Staging tested changes for commit",
  "directory": "/Users/ddahl/code/memetic-research-labs-llc/vapor",
  "updated_at": "2026-05-06T12:34:56Z",
  "message_count": 2903,
  "index_status": {
    "status": "partial",
    "can_search": true,
    "needs_update": true,
    "needs_repair": false,
    "chunks": 3042,
    "vectors": 2181,
    "coverage": 0.717,
    "model": "MiniLM all-MiniLM-L6-v2",
    "message": "Search is usable but incomplete. Ask the user to click Update Search if recall matters."
  }
}
```

### Index Status

```http
GET /api/agent/index/status
```

Optional query parameters:

- `session_id`: explicit session ID.
- `cwd`: infer the session from a working directory.
- `source`: source adapter, currently `opencode`.

Example:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/index/status?session_id=ses_abc123" \
  | python3 -m json.tool
```

Important fields:

- `can_search`: whether agents can use search now.
- `needs_update`: search is usable but stale or incomplete.
- `needs_repair`: search is unavailable until repaired.
- `chunks`: indexed metadata chunks.
- `vectors`: searchable vectors available.
- `coverage`: `vectors / chunks`.
- `message`: user-facing guidance.

### Search Agent Memory

```http
GET /api/agent/search
```

Query parameters:

- `q`: required search query.
- `session_id`: optional explicit session ID.
- `limit`: optional result limit, default `20`.

Example with inferred session:

```bash
QUERY="why did sqlite vec search fail"
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/search?q=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")&limit=10" \
  | python3 -m json.tool
```

Explicit session route:

```http
GET /api/agent/sessions/{session_id}/search
```

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/sessions/ses_abc123/search?q=sqlite%20vec%20filtering&limit=10" \
  | python3 -m json.tool
```

Response shape:

```json
{
  "results": [
    {
      "embedding_id": "turn:ses_...:msg_...:0",
      "distance": 0.211,
      "chunk_text": "Relevant indexed text...",
      "turn_source_id": "msg_...",
      "session_id": "ses_...",
      "chunk_index": 0
    }
  ],
  "count": 1
}
```

The score is **cosine distance**. Lower is better.

- `0.0` is closest.
- `< 0.30` is usually a strong match.
- `< 0.60` is usually related.
- Higher values are weaker.

### Expand Context

```http
GET /api/agent/sessions/{session_id}/context
```

Query parameters:

- `q`: required query used to find relevant context.
- `context_turns`: optional surrounding turn count, default `2`.

Example:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE/api/agent/sessions/ses_abc123/context?q=sqlite%20vec%20filtering&context_turns=2" \
  | python3 -m json.tool
```

Agents should expand context before relying on a search result for a detailed answer.

## Agent Workflow

Recommended agent behavior:

1. Call `/api/agent/current-session?cwd=...`.
2. Read `index_status`.
3. If `can_search` is false, report `message` to the user and stop.
4. If `can_search` is true, call `/api/agent/search` or `/api/agent/sessions/{id}/search`.
5. Use `/api/agent/sessions/{id}/context` before relying on a result.

Example decision mapping:

- `missing`: ask the user to click **Import & Index**.
- `repair_needed`: ask the user to click **Repair Search**.
- `partial`: search is usable, but mention that **Update Search** improves recall.
- `dirty`: search is usable, but **Update Search** will include newer data.
- `ready`: search normally.

## Skill Installation

Install the local agent skill files with:

```bash
scripts/install-vapor-skill.sh
```

This installs:

- `~/.opencode/skills/vapor-agent-memory`
- `~/.claude/skills/vapor-agent-memory`

## Privacy and Storage

- API is bound to localhost.
- Bearer token authentication is required.
- OpenCode data is read from the local OpenCode SQLite database.
- Embeddings are generated locally using MiniLM `all-MiniLM-L6-v2`.
- Vectors are stored locally in `~/Library/Application Support/Vapor/vectors.db`.

## Troubleshooting

### `401 Unauthorized`

The token is missing or incorrect. Ensure `VAPOR_API_TOKEN` is set and passed as a bearer token.

### `missing`

The session has not been imported. Open the session in Vapor and click **Import & Index**.

### `repair_needed`

Imported content exists, but no usable vectors are available. Click **Repair Search** in Vapor.

### `partial`

Search is usable, but some vectors are missing. Click **Update Search** for better recall.

### No current session

Pass an explicit `session_id`, or call the endpoint with a `cwd` that maps to a known OpenCode session.

## Limitations

- OpenCode is the first supported source.
- Broader trace segmentation for reasoning, tool inputs, tool outputs, patch summaries, and step summaries is planned.
- A dedicated `vapor-memory` CLI wrapper is planned; HTTP is the canonical API.
