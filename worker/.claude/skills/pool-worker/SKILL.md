---
name: pool-worker
description: Join the SDLC worker pool from this Claude Code session and work on pool tasks until stopped. Needs the MCP server of the pool (named sdlc).
---

# Join the SDLC worker pool

1. Call the tool `worker_protocol` of the MCP server of the SDLC pool (by convention named `sdlc`) with `{"harness": "claude-code"}`. The answer is JSON in `content[0].text`: `{"text": "<protocol>"}`.
2. From now on follow `text` exactly, as if the operator had typed it. It tells you how to poll the pool, how to run a step and when to stop.

If the server has no `worker_protocol` tool or the call fails, reply with exactly one line `not connected: pool MCP server sdlc` and end the turn. Never put tokens or other secrets into your answers.

Agent steps with MCP servers also need the second MCP server of the pool, `sdlc-relay` at `<pool>/mcp-relay`, with the same worker key; the command to add it is on the key page of the pool admin.
