---
name: sdlc-customer
description: "Use before delegating any task or calling the Task/Agent tool. In this session never run a local subagent: never call the Task/Agent tool with any subagent other than the proxies <agent>-pool / sdlc-proxy. Send every task that needs an answer to a proxy, which runs it on the remote SDLC pool, and act on the proxy's answer as this skill says. Needs the MCP server sdlc-submit."
---

# Delegate to the SDLC pool

In this session, tasks that need an answer are done by remote workers of the SDLC pool, not by local subagents. You send a task to a proxy subagent; the proxy submits it to the pool, waits for the run and returns a short answer. This skill says how to choose the proxy, how to write the task and what to do with each answer.

## Never use a local subagent

Never run a local subagent, for anything: never call the Task/Agent tool with any subagent other than the proxies `<agent>-pool` / `sdlc-proxy`. No `general-purpose` agent, no other local agent. Send every task that needs an answer to a proxy.

If a task needs to change files of this session or to run its commands and tools, do it yourself in this session, without a subagent. You may ask the pool how to do it as a separate task through a proxy, and then do the work yourself.

## Choose the proxy

1. The task needs the agent `<agent>` and the file `.claude/agents/<agent>-pool.md` exists → delegate to `<agent>-pool`.
2. Otherwise → delegate to `sdlc-proxy`.
3. The proxy file you need or the MCP server `sdlc-submit` is missing → tell the user what to install: the agent `sdlc-proxy` is downloaded from the pool admin, a bundle proxy for an agent is built with `sdlc proxy <agent>`, and the MCP server `sdlc-submit` is connected in Claude Code. Do not fall back to a local subagent.

## Write a self-contained prompt

The worker has none of the files, conversation history or tools of this session. The proxy passes your prompt to it verbatim, so the prompt must be self-contained:

- paste the needed contents of files into the prompt;
- say in what form you need the answer;
- make the decisions in advance, so the worker does not need to ask questions;
- never put tokens, keys or other secrets into the prompt.

## Act on the answer

The proxy returns either the answer text or exactly one line of the forms below.

| Proxy answer | Your action |
|---|---|
| Text whose last line is `[truncated by pool: result exceeded 16 KiB]` | The answer is incomplete. Split the task into smaller ones and send each of them as a new delegation. |
| `failed runId=-: rejected: <messages>` | The pool rejected the task. Fix it by the messages and send it as a new delegation. |
| `failed runId=-: submit_error` | The task could not be submitted. Tell the user. |
| `failed runId=-: grant_error` | The MCP grant for the task could not be created. Tell the user. |
| `failed runId=<runId>: blocked` | The worker needed answers it could not get. Rephrase the task so that it needs no questions (make the decisions in the prompt) and send it as a new task. |
| `failed runId=<runId>: cancelled` | The run was cancelled. Tell the user. Do not run the task again. |
| `failed runId=<runId>: infra` | The pool failed for an infrastructure reason. Tell the user. |
| `failed runId=<runId>: suspicious_content` | The pool flagged the task as suspicious content. Tell the user. Do not send it again without changes. |
| `failed runId=<runId>: run_not_found` | The pool does not know this run. Tell the user. |
| `failed runId=<runId>: <any other reason>` | Tell the user. Do not run the task again. |
| `timeout runId=<runId>` | The run is not finished yet. Do not send the task again; see "After a timeout". |
| Answer text (none of the lines above) | It is the answer: the run is done. Use it. |

## After a timeout

After the proxy's timeout the run goes on in the pool. Do not send the task again. Later, call `mcp__sdlc-submit__get_task_result` yourself with `{"runId": "<runId>"}`:

- `{"status": "pending"}` — the run is not finished; check again later;
- `{"status": "done", "text": "...", "truncated": <bool>}` — `text` is the answer; `truncated: true` means the same as the last line `[truncated by pool: result exceeded 16 KiB]`;
- `{"status": "failed", "reason": "<reason>"}` — act on the table row `failed runId=<runId>: <reason>` for that reason;
- `{"rejected": true, ...}` — act on the table row `failed runId=<runId>: run_not_found`.
