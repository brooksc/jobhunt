import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { cleanupDb, tempDbPath } from '../helpers.js';

const dbPaths = [];

after(() => {
  for (const dbPath of dbPaths) cleanupDb(dbPath);
});

async function withMcpClient(fn) {
  const dbPath = tempDbPath();
  dbPaths.push(dbPath);
  const client = new Client({ name: 'jobhunt-test', version: '0.0.0' });
  const transport = new StdioClientTransport({
    command: 'node',
    args: ['server/mcp.js', '--db-path', dbPath],
  });
  await client.connect(transport);
  try {
    await fn(client);
  } finally {
    await client.close();
  }
}

function parseToolResult(result) {
  assert.equal(result.content.length, 1);
  assert.equal(result.content[0].type, 'text');
  return JSON.parse(result.content[0].text);
}

describe('jobhunt MCP server', () => {
  it('lists tools and can create/list a capture', async () => {
    await withMcpClient(async client => {
      const tools = await client.listTools();
      assert.ok(tools.tools.some(tool => tool.name === 'add_capture'));
      assert.ok(tools.tools.some(tool => tool.name === 'jobs_list'));

      const created = parseToolResult(await client.callTool({
        name: 'add_capture',
        arguments: {
          url: 'https://example.com/jobs/1',
          page_title: 'Role',
          visible_text: 'Senior engineer role',
        },
      }));
      assert.equal(created.ok, true);
      assert.equal(created.duplicate, false);
      assert.ok(created.capture_id);

      const jobs = parseToolResult(await client.callTool({
        name: 'jobs_list',
        arguments: { limit: 5 },
      }));
      assert.equal(jobs.length, 1);
      assert.equal(jobs[0].source_url, 'https://example.com/jobs/1');
      assert.equal(jobs[0].extraction_status, 'pending');
    });
  });
});
