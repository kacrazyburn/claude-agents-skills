// Pure render: `node scripts/render.mjs <key>` writes the bytes of <key>, as the engine renders them,
// to stdout. Writes no files and compares nothing (the Makefile does). Runs in NODE_IMAGE over a built
// engine checkout.
//
// Env: ENGINE_DIR — absolute path of the built engine; PUBLIC_URL — public base URL of the pool server.
// Exit: 0 — OK; 2 — unknown key, missing env, or the engine output no longer has the expected shape.
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

function fail(message) {
  process.stderr.write(`render: ${message}\n`);
  process.exit(2);
}

const key = process.argv[2];
const engineDir = process.env.ENGINE_DIR;
const publicUrl = process.env.PUBLIC_URL;
if (!engineDir) fail('ENGINE_DIR is not set');
if (!publicUrl) fail('PUBLIC_URL is not set');

const load = (rel) => import(pathToFileURL(join(engineDir, rel)).href);

// The customer MCP command is not exported by the engine: take it from the submitter instructions.
async function customerCommand() {
  const { SUBMIT_MCP_SERVER } = await load('packages/contracts/dist/index.js');
  const { renderSubmitterInstructions } = await load('apps/server/dist/admin/submitter-instructions.js');
  const html = renderSubmitterInstructions({ clientId: '-', token: '<token>', publicUrl });
  const match = /<pre><code>([^<]*)<\/code><\/pre>/.exec(html);
  const command = match
    ? match[1]
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
    : '';
  if (!command.startsWith('claude mcp add ') || !command.includes(SUBMIT_MCP_SERVER)) {
    fail('submitter command not found in engine output');
  }
  return command;
}

const KEYS = {
  'customer/.claude/skills/sdlc-customer/SKILL.md': async () =>
    (await load('packages/contracts/dist/index.js')).renderCustomerSkill(),
  'customer/.claude/agents/sdlc-proxy.md': async () =>
    (await load('packages/contracts/dist/index.js')).renderProxyAgent(),
  'worker/.claude/skills/pool-worker/SKILL.md': async () =>
    (await load('apps/server/dist/pool-skill.js')).renderPoolSkill('claude-code'),
  // Lines README.md must contain verbatim, one per line.
  'readme-lines': async () => {
    const { mcpAddCommand, relayMcpAddCommand } = await load('apps/server/dist/admin/worker-instructions.js');
    const { WORKER_PROMPT_NAME } = await load('apps/server/dist/worker-prompt.js');
    const lines = [
      mcpAddCommand('<token>', publicUrl),
      relayMcpAddCommand('<token>', publicUrl),
      await customerCommand(),
      `/mcp__sdlc__${WORKER_PROMPT_NAME}`,
    ];
    return `${lines.join('\n')}\n`;
  },
};

const render = Object.hasOwn(KEYS, key ?? '') ? KEYS[key] : null;
if (!render) fail(`unknown key "${key ?? ''}" (known: ${Object.keys(KEYS).join(', ')})`);
process.stdout.write(await render());
