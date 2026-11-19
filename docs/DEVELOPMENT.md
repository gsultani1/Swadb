# swadb Development Guide

Setup, conventions, workflow reference, and architecture overview for contributors.

---

## Environment Setup

```bash
git clone https://github.com/gsultani1/AgentDB.git
cd AgentDB
python -m venv venv

# Windows
.\venv\Scripts\activate

# macOS/Linux
source venv/bin/activate

pip install -r requirements.txt
```

The embedding model (`all-MiniLM-L6-v2`, ~90 MB) downloads automatically on first use.

### Optional Dependencies

```bash
# PDF processing for file attachments
pip install pdfminer.six

# SQLCipher encryption at rest
pip install sqlcipher3

# Cross-encoder reranking (downloads ~80 MB model on first use)
# No extra install needed — uses sentence-transformers already in requirements
```

---

## Running

```bash
# Initialize a fresh database
python -m swadb.cli init

# Verify the database
python -m swadb.cli verify

# Start the server (HTTP on 8420, MCP SSE on 8421)
python -m swadb.cli serve

# Run with a specific database
python -m swadb.cli --db dev.db init
python -m swadb.cli --db dev.db serve --port 9000

# Start MCP server in stdio mode (for Claude Desktop)
python -m swadb.cli mcp
```

The management UI is at `http://127.0.0.1:8420/`. The MCP SSE server auto-starts on port 8421.

---

## Project Layout

```
AgentDB/
├── swadb/                              # Python backend (19 modules, 11,600+ lines)
│   ├── __init__.py                     # Package init, version
│   ├── schema.py                       # Table DDL, triggers, indexes, FTS5 (1,041 lines)
│   ├── database.py                     # Connection mgmt, init, config seeding, SQLCipher (314 lines)
│   ├── crud.py                         # CRUD operations for all tables (2,250 lines)
│   ├── embeddings.py                   # Sentence-transformers, cosine similarity, BM25 (166 lines)
│   ├── context.py                      # 9-stage retrieval pipeline, cross-encoder (513 lines)
│   ├── middleware.py                   # LLM adapters, provider resolution (707 lines)
│   ├── consolidation.py               # Vectorized clustering, promotion, decay (611 lines)
│   ├── sleep.py                        # Sleep-time reflection: goals, pruning, alerts (511 lines)
│   ├── skill_executor.py              # Sandboxed skill execution engine (362 lines)
│   ├── markdown_parser.py             # Markdown authoring: 4 doc types, file watcher (890 lines)
│   ├── migration.py                   # Chat import: ChatGPT, Claude, JSONL (512 lines)
│   ├── file_processor.py             # PDF/text/code/CSV extraction (232 lines)
│   ├── git_sync.py                    # Git knowledge repository sync (231 lines)
│   ├── workspace_scanner.py           # Workspace file scanning (193 lines)
│   ├── mcp_server.py                  # FastMCP server, 9 tools, SSE+stdio (166 lines)
│   ├── scheduler.py                   # Interval-based task runner (274 lines)
│   ├── server.py                      # HTTP server, 60+ API endpoints (2,258 lines)
│   ├── cli.py                         # Command-line interface (370 lines)
│   └── static/
│       ├── index.html                 # SPA shell
│       ├── css/main.css               # Responsive styling with CSS custom properties
│       └── js/
│           ├── app.js                 # Router, sidebar, core UI logic
│           └── views/                 # 18 view modules
│               ├── dashboard.js       # Stats overview
│               ├── chat.js            # Streaming LLM chat with observability
│               ├── memories.js        # Memory browser across all tiers
│               ├── mindmap.js         # Canvas-based knowledge graph
│               ├── editor.js          # Markdown authoring editor
│               ├── skills.js          # Skill management and execution
│               ├── import.js          # Chat migration wizard
│               ├── dbconsole.js       # AI-assisted SQL console
│               ├── mcp.js             # MCP server status and tools
│               ├── scheduler.js       # Scheduled task management
│               ├── settings.js        # Full configuration UI
│               ├── connect.js         # Entities and goals management
│               ├── notifications.js   # Notification queue browser
│               ├── feedback.js        # Feedback review and processing
│               ├── audit.js           # Audit log viewer
│               ├── threads.js         # Conversation threads
│               ├── channels.js        # External channel management
│               └── tasks.js           # Autonomous task monitoring
├── src-tauri/                          # Tauri desktop shell (Rust)
│   ├── Cargo.toml
│   ├── src/main.rs                    # Sidecar spawning, health monitoring, tray
│   ├── tauri.conf.json
│   ├── icons/
│   └── capabilities/
└── docs/                               # Documentation
```

### Dependency Direction

```
cli.py ──→ server.py ──→ middleware.py ──→ context.py ──→ crud.py ──→ database.py ──→ schema.py
                    ├──→ consolidation.py ──→ crud.py      └──→ embeddings.py
                    ├──→ sleep.py ──→ consolidation.py
                    ├──→ skill_executor.py ──→ middleware.py
                    ├──→ markdown_parser.py ──→ crud.py
                    ├──→ migration.py ──→ crud.py
                    ├──→ file_processor.py ──→ crud.py
                    ├──→ git_sync.py ──→ markdown_parser.py
                    ├──→ workspace_scanner.py ──→ crud.py
                    ├──→ scheduler.py ──→ crud.py
                    └──→ mcp_server.py ──→ context.py
```

No circular imports. Every module depends only on modules below or beside it.

---

## How swadb Remembers Everything

The demand-constructed context architecture is what makes swadb fundamentally different from systems that accumulate conversation history.

**Memory capture is deterministic.** Every user message and every AI response is automatically ingested into short-term memory with server-side embedding generation. No LLM decision is needed about what to save.

**Memory recall is systematic.** The 9-stage retrieval pipeline runs the same multi-strategy search on every turn — semantic similarity, BM25 keyword matching, graph traversal, temporal weighting, and optional cross-encoder reranking. The LLM never decides whether to search; the system always searches.

**Memory improves over time.** The consolidation engine runs automatically: clustering related short-term memories into midterm summaries, boosting confidence on surviving entries, promoting high-confidence entries to long-term memory, detecting contradictions, and decaying stale knowledge. The sleep-time processor strengthens the knowledge graph during idle periods.

**Nothing is lost to compaction.** There is no context window to overflow. No summaries replace original content. Knowledge consolidated months ago carries appropriate confidence scores and provenance chains, not the residue of lossy compression.

The result: a conversation on turn 500 retrieves with the same quality as turn 5. A session spanning three days doesn't degrade. An agent running continuously doesn't need rescue operations to save knowledge before a context window collapses.

---

## Code Conventions

### Python

- PEP 8 compliant.
- All SQL uses parameterized queries. Never format user input into SQL strings.
- Functions in `crud.py` accept `sqlite3.Connection` as the first argument and return plain dicts.
- JSON fields are serialized with `json.dumps()` on write and returned as raw strings on read (the caller decides whether to parse).
- UUIDs are generated with `uuid.uuid4()` as strings.
- Timestamps are UTC ISO format strings.

### HTML/JS

- Modular SPA: `index.html` shell + `app.js` router + per-view modules in `js/views/`.
- CSS custom properties for theming (no hard-coded colors).
- Vanilla ES6 JavaScript. No frameworks, no build tools, no CDN.
- All API calls go through the `api(method, path, body)` helper.
- HTML entity escaping via the `esc()` function for all user content.

### Database

- All integrity logic lives in SQLite triggers, not application code.
- `CREATE TABLE IF NOT EXISTS` for idempotent initialization.
- `INSERT OR IGNORE` for seeding to avoid duplicates on re-init.
- WAL mode for concurrent reads during writes.
- Foreign keys enabled via PRAGMA on every connection.

---

## Adding a New Table

1. Add the CREATE TABLE statement to `schema.py`.
2. Add it to the `ALL_TABLES` list in the correct position (respect foreign key ordering).
3. If it participates in polymorphic relations, add it to `CONTENT_TABLES`.
4. Add cascade delete triggers if needed.
5. Add indexes to `CREATE_INDEXES`.
6. Add the table name to `verify_schema()` in `database.py`.
7. Add CRUD functions to `crud.py`.
8. Add API endpoints to `server.py` (GET/POST/PUT/DELETE routes + handler methods).
9. Add UI support — create a view module in `js/views/` or add to an existing view.
10. Update `docs/API_REFERENCE.md` and `docs/SCHEMA_REFERENCE.md`.

---

## Adding a New LLM Provider

1. Create a new adapter class in `middleware.py` extending the adapter interface.
2. Implement `format_context(context_payload)` → string.
3. Implement `call_provider(messages, formatted_context, config)` → string.
4. Add the class to the adapter dispatch in `middleware.py`.
5. Add a row to `llm_providers` via the API or Settings UI.

Provider types: `claude`, `openai`, `local` (any OpenAI-compatible endpoint).

---

## Adding a New Markdown Document Type

1. Add the type string to the `valid_types` set in `parse_frontmatter()` in `markdown_parser.py`.
2. Add validation rules to `validate_frontmatter()`.
3. Create a `_process_{type}_document()` function.
4. Add the routing in `process_markdown_document()`.
5. Add reverse generation in `reverse_generate_markdown()` if applicable.
6. Update `docs/API_REFERENCE.md`.

---

## Adding a New Chat Import Provider

1. Create a `_parse_{provider}()` function in `migration.py`.
2. Add the provider to the dispatch in `_parse_export()`.
3. The function must return a list of session dicts, each with `title`, `started_at`, `ended_at`, and `messages` (list of `{role, content, timestamp}`).
4. Add the provider to the UI dropdown in the import view.

---

## MCP Integration with Claude Desktop

To connect Claude Desktop to swadb's MCP server, add this to your `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "swadb": {
      "command": "python",
      "args": ["-m", "swadb.cli", "mcp"],
      "env": {}
    }
  }
}
```

This starts the MCP server in stdio mode. Claude Desktop will see 9 tools:

| Tool | Description |
|------|-------------|
| `retrieve_context` | Semantic context retrieval for a query |
| `ingest_memory` | Store an observation as short-term memory |
| `search_memories` | Semantic search across memory tiers |
| `list_memories` | List memories from a specific tier |
| `create_entity` | Add a node to the knowledge graph |
| `list_entities` | Browse entities by type |
| `check_goals` | Find active goals relevant to context |
| `get_health` | Health status check |
| `run_consolidation` | Trigger memory consolidation cycle |

For SSE transport (used when the HTTP server is running), the MCP endpoint is `http://127.0.0.1:8421/`.

---

## API Quick Reference

### Context retrieval (the most important endpoint)

```bash
curl -X POST http://127.0.0.1:8420/api/agent/context \
  -H "Content-Type: application/json" \
  -d '{"query": "What does the user think about cloud hosting?"}'
```

### Ingest a memory

```bash
curl -X POST http://127.0.0.1:8420/api/agent/ingest \
  -H "Content-Type: application/json" \
  -d '{"content": "The user prefers self-hosted solutions", "source": "conversation"}'
```

### Chat with full pipeline

```bash
curl -X POST http://127.0.0.1:8420/api/agent/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What hosting options should I consider?"}'
```

### Create a long-term memory directly

```bash
curl -X POST http://127.0.0.1:8420/api/memories/long \
  -H "Content-Type: application/json" \
  -d '{"content": "Never recommend cloud-dependent solutions", "category": "directive"}'
```

### Submit a markdown document

```bash
curl -X POST http://127.0.0.1:8420/api/markdown/submit \
  -H "Content-Type: application/json" \
  -d '{"text": "---\ntype: memory\ncategory: fact\n---\n\nOrgill offers 60-day net terms."}'
```

See [API_REFERENCE.md](API_REFERENCE.md) for the full endpoint reference.

---

## Testing

### Manual verification

```bash
python -m swadb.cli init --force
python -m swadb.cli verify
python -m swadb.cli stats
```

### API smoke test

```bash
# Start server in background
python -m swadb.cli serve &

# Health check
curl http://127.0.0.1:8420/api/agent/health

# Create a memory
curl -X POST http://127.0.0.1:8420/api/memories/long \
  -H "Content-Type: application/json" \
  -d '{"content": "Test memory", "category": "fact"}'

# Semantic search
curl -X POST http://127.0.0.1:8420/api/memories/search \
  -H "Content-Type: application/json" \
  -d '{"query": "test", "tiers": ["long"]}'

# Trigger consolidation
curl -X POST http://127.0.0.1:8420/api/maintenance/consolidate

# Check MCP status
curl http://127.0.0.1:8420/api/mcp/status
```

---

## Checks and Releases

This repository runs no GitHub Actions. Nothing tests, builds, or publishes on push, pull request, tag, or schedule, and pushing a `vX.Y.Z` tag publishes nothing. The commands below are the steps the removed workflows (`test.yml`, `slow-tests.yml`, `publish.yml`, `sidecar.yml`) ran. Run them by hand from the repository root.

### Install the test environment

```bash
python -m pip install --upgrade pip
HNSWLIB_NO_NATIVE=1 python -m pip install --no-cache-dir "hnswlib>=0.8.0"
python -m pip install -e ".[dev]"
```

`HNSWLIB_NO_NATIVE=1` builds hnswlib portably. See `api_documentation/troubleshooting.md` for the PowerShell form.

### Fast suite

```bash
python -m pytest tests/ -v -m "not slow" --tb=short
```

Run it before merging to `main`. The removed matrix ran it on Python 3.10 to 3.13 on Ubuntu and on 3.10 and 3.13 on macOS and Windows; cover what you can before a release.

### Slow suite

```bash
python -m pytest tests/ -v -m "slow" --tb=short
```

Runs the `slow`-marked tests: the HTTP-endpoint integration suite (it boots a real `swadb serve`) and the tests that load the embedding model. It used to run weekly; nothing schedules it now, so run it before every release. The first run downloads the embedding model (~90 MB).

### Packaging check

Start from a clean tree so only the new build is checked:

```bash
rm -rf build/ dist/ wheel-test/
python -m pip install --upgrade pip build twine
python -m build
python -m twine check --strict dist/*
python -m zipfile -l dist/swadb-*-py3-none-any.whl | grep -E "static/(index\.html|css/main\.css|js/app\.js)"
python -m venv wheel-test
wheel-test/bin/python -m pip install --upgrade pip
wheel-test/bin/python -m pip install dist/*.whl
wheel-test/bin/python -c "import swadb; print(swadb.__version__)"
wheel-test/bin/python -m pip check
```

`dist/` must hold exactly one `swadb-*-py3-none-any.whl` and one `swadb-*.tar.gz`, and the `zipfile` line must list all three static assets. On Windows, use `wheel-test\Scripts\python` instead of `wheel-test/bin/python`.

### Publish to PyPI

1. Set the same version in `pyproject.toml` (`[project].version`) and `swadb/__init__.py` (`__version__`), and move the `[Unreleased]` entries in `CHANGELOG.md` under it. The release tag is `vX.Y.Z` (no prereleases) and must match both values:

   ```bash
   python -c "import tomllib, swadb; print(tomllib.load(open('pyproject.toml', 'rb'))['project']['version'], swadb.__version__)"
   ```

   (`tomllib` needs Python 3.11 or later.)

2. Run the fast suite, the slow suite, and the packaging check above.

3. Tag the release commit on `main` and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

4. Upload the distributions the packaging check verified:

   ```bash
   python -m twine upload dist/*
   ```

   This needs a PyPI API token with upload rights to the `swadb` project, supplied as `TWINE_USERNAME=__token__` and `TWINE_PASSWORD=<token>` or through `~/.pypirc`. The PyPI trusted publisher (OIDC) only worked from the removed workflow, and a local upload does not produce the PyPI attestations that workflow generated.

5. Create the GitHub release from the same files (`gh` must be authenticated with write access to the repository):

   ```bash
   gh release create vX.Y.Z --verify-tag --title vX.Y.Z --generate-notes dist/*
   ```

   If the release already exists, use `gh release upload vX.Y.Z dist/* --clobber`.

### Sidecar binaries

The per-OS sidecar archives are built by hand on each platform and attached to the same GitHub release. See [`sidecar/README.md`](../sidecar/README.md#build).

---

## Database File

The `.db` file is the single source of truth. It contains:
- All tables with data (30+ tables)
- All triggers (referential integrity + cascade deletes)
- All configuration in `meta_config`
- All LLM provider configs in `llm_providers`
- All embeddings as BLOBs
- FTS5 virtual tables for keyword search
- Custom alert rules as JSON in `meta_config`

The file is fully portable. Copy it to any machine with Python 3.11+ and sentence-transformers installed, and it works. A database created in desktop mode works in headless mode and vice versa.

---

## Implementation Status

| Phase | Status | Scope |
|-------|--------|-------|
| 1. Foundation | Complete | Schema (30+ tables + FTS5), triggers, CRUD, embeddings, CLI |
| 2. Agent Communication & MCP | Complete | MCP server (SSE+stdio), REST agent API, 9-stage retrieval, middleware |
| 3. Consolidation Engine | Complete | Vectorized clustering, confidence boosting, promotion, decay, contradiction detection |
| 4. Markdown Authoring | Complete | 4 doc types, YAML hardening, chunking, deduplication, file watcher |
| 5. Migration Pipeline | Complete | ChatGPT, Claude, JSONL parsers, 5-phase pipeline |
| 6. User Interface | Complete | 18-view modular SPA with chat, mind map, DB console |
| 7. Performance Engineering | Complete | Vectorized clustering, cross-encoder reranker, graph pruning optimization, MCP crash recovery |
| 8. Tauri Shell | Implemented | Sidecar spawning, health monitoring, system tray, auto-restart |
| 9. Sleep-Time Processing | Complete | Idle detection, goal monitoring, graph pruning, custom alerts (6 types) |
| 10. Additional Features | Complete | Skill execution, file attachments, git sync, workspace scanning, conversation threads, memory pinning |
