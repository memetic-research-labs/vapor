---
name: vapor-session-search
description: "Search indexed OpenCode agent sessions via Vapor's local HTTP API. Supports semantic vector search across conversation turns and per-session context retrieval."
---

# Vapor Session Search

Search indexed agent conversation sessions through Vapor's embedded HTTP API on `127.0.0.1:8766`.

## Prerequisites

- Vapor must be running (macOS app with embedded HTTP server on port 8766)
- Auth token available via `VAPOR_API_TOKEN` environment variable (auto-set by Vapor on launch)
- Sessions must be indexed via "Import & Index" in the Vapor UI before they are searchable

## Authentication

All requests require a Bearer token. Use the `VAPOR_API_TOKEN` environment variable:

```bash
TOKEN=$VAPOR_API_TOKEN
curl -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8766/api/session/search?q=..."
```

## API Endpoints

### Search Sessions

Semantic vector search across indexed conversation turns.

```bash
TOKEN=$VAPOR_API_TOKEN

# Search all indexed sessions
curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8766/api/session/search?q=implement+authentication&limit=10" | python3 -m json.tool

# Search within a specific session
curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8766/api/session/search?q=error+handling&session_id=ses_abc123&limit=5" | python3 -m json.tool
```

**Parameters:**
- `q` (required): Search query text
- `session_id` (optional): Scope search to a specific session
- `limit` (optional, default 20): Max results to return

**Response:**
```json
{
  "results": [
    {
      "embedding_id": "turn:ses_abc123:msg_def456:0",
      "distance": 0.42,
      "chunk_text": "...relevant text from conversation...",
      "turn_source_id": "msg_def456",
      "session_id": "ses_abc123",
      "chunk_index": 0
    }
  ],
  "count": 1
}
```

### Get Session Context

Retrieve search results with full chunk context from surrounding turns.

```bash
TOKEN=$VAPOR_API_TOKEN

curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:8766/api/session/ses_abc123/context?q=authentication+flow&context_turns=2" | python3 -m json.tool
```

**Parameters:**
- `session_id` (required, in URL path): Session to search
- `q` (required): Search query
- `context_turns` (optional, default 2): Number of surrounding turns to include
- `limit` (optional, default 5): Max search results

**Response:**
```json
{
  "session_id": "ses_abc123",
  "query": "authentication flow",
  "results": [...],
  "turn_chunks": [
    {
      "embedding_id": "turn:ses_abc123:msg_def456:0",
      "chunk_text": "...full chunk text...",
      "turn_source_id": "msg_def456",
      "session_id": "ses_abc123",
      "chunk_index": 0
    }
  ],
  "unique_turns": ["msg_def456"]
}
```

### Health Check

```bash
curl -s "http://127.0.0.1:8766/api/status" | python3 -m json.tool
```

## Usage Tips

- Search queries work best with natural language descriptions of what you're looking for
- The vector search uses MiniLM paraphrase-multilingual-L12-v2 embeddings (semantic similarity, not keyword matching)
- Sessions must be manually indexed via "Import & Index" in Vapor's session window before they appear in search results
- Each session's conversation is chunked into 512-character segments with 32-character overlap for granular matching
- Only user and assistant text turns are indexed (tool calls, reasoning, patches are excluded)
