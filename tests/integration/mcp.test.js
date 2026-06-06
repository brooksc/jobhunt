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

describe('MCP job_get', () => {
  it('returns full job with events', async () => {
    await withMcpClient(async client => {
      await client.callTool({
        name: 'add_capture',
        arguments: { url: 'https://example.com/mcp-get', page_title: 'Get Test Job', visible_text: 'Detailed job description for testing job_get tool.' },
      });
      const jobs = parseToolResult(await client.callTool({ name: 'jobs_list', arguments: { limit: 1 } }));
      const jobId = jobs[0].job_id;

      const result = parseToolResult(await client.callTool({ name: 'job_get', arguments: { job_id: jobId } }));
      assert.ok(result.job);
      assert.equal(result.job.job_id, jobId);
      assert.equal(result.job.source_url, 'https://example.com/mcp-get');
      assert.ok(Array.isArray(result.events));
    });
  });
});

describe('MCP jobs_list with status filter', () => {
  it('filters jobs by status', async () => {
    await withMcpClient(async client => {
      await client.callTool({ name: 'add_capture', arguments: { url: 'https://example.com/mcp-filter', page_title: 'Filter Job', visible_text: 'Job for status filter test.' } });
      const jobs = parseToolResult(await client.callTool({ name: 'jobs_list', arguments: { limit: 1 } }));
      const jobId = jobs[0].job_id;
      await client.callTool({ name: 'set_job_status', arguments: { job_id: jobId, status: 'applied' } });

      const applied = parseToolResult(await client.callTool({ name: 'jobs_list', arguments: { limit: 10, status: 'applied' } }));
      assert.ok(applied.every(j => j.status === 'applied'));
      assert.ok(applied.some(j => j.job_id === jobId));

      const saved = parseToolResult(await client.callTool({ name: 'jobs_list', arguments: { limit: 10, status: 'saved' } }));
      assert.ok(saved.every(j => j.status === 'saved'));
    });
  });
});

describe('MCP job management tools', () => {
  it('update_job, set_job_status, add_job_note, rerun_extraction', async () => {
    await withMcpClient(async client => {
      await client.callTool({
        name: 'add_capture',
        arguments: { url: 'https://example.com/mcp-mgmt', page_title: 'Job', visible_text: 'Job description text here.' },
      });
      const jobs = parseToolResult(await client.callTool({ name: 'jobs_list', arguments: { limit: 1 } }));
      const jobId = jobs[0].job_id;

      const updated = parseToolResult(await client.callTool({
        name: 'update_job',
        arguments: { job_id: jobId, company: 'TestCo', title: 'Senior TPM' },
      }));
      assert.equal(updated.ok, true);
      assert.equal(updated.job_id, jobId);

      const statusResult = parseToolResult(await client.callTool({
        name: 'set_job_status',
        arguments: { job_id: jobId, status: 'applied' },
      }));
      assert.equal(statusResult.ok, true);
      assert.equal(statusResult.status, 'applied');

      const noteResult = parseToolResult(await client.callTool({
        name: 'add_job_note',
        arguments: { job_id: jobId, note: 'Follow up next week' },
      }));
      assert.equal(noteResult.ok, true);

      const rerunResult = parseToolResult(await client.callTool({
        name: 'rerun_extraction',
        arguments: { job_id: jobId },
      }));
      assert.equal(rerunResult.ok, true);
      assert.equal(rerunResult.extraction_status, 'pending');
    });
  });
});

describe('MCP site management tools', () => {
  it('add_site, update_site, list_sites, delete_site', async () => {
    await withMcpClient(async client => {
      const added = parseToolResult(await client.callTool({
        name: 'add_site',
        arguments: { url: 'https://careers.acme.com/jobs', page_title: 'Acme Careers' },
      }));
      assert.ok(added.id);
      assert.equal(added.origin, 'https://careers.acme.com');
      const siteId = added.id;

      const sites = parseToolResult(await client.callTool({ name: 'list_sites', arguments: {} }));
      assert.ok(Array.isArray(sites));
      assert.equal(sites.length, 1);

      const updated = parseToolResult(await client.callTool({
        name: 'update_site',
        arguments: { site_id: siteId, note: 'Updated note' },
      }));
      assert.equal(updated.note, 'Updated note');

      const deleted = parseToolResult(await client.callTool({
        name: 'delete_site',
        arguments: { site_id: siteId },
      }));
      assert.equal(deleted.ok, true);

      const after = parseToolResult(await client.callTool({ name: 'list_sites', arguments: {} }));
      assert.equal(after.length, 0);
    });
  });
});

describe('MCP updateSite remaining branch coverage', () => {
  it('covers next_review_days, jobs_url, and company_description TRUE branches', async () => {
    await withMcpClient(async client => {
      const added = parseToolResult(await client.callTool({
        name: 'add_site',
        arguments: { url: 'https://remaining-branches.example.com/jobs' },
      }));
      const siteId = added.id;
      const result = parseToolResult(await client.callTool({
        name: 'update_site',
        arguments: {
          site_id: siteId,
          next_review_days: 3,
          jobs_url: 'https://remaining-branches.example.com/openings',
          company_description: 'A company that builds great things.',
        },
      }));
      assert.equal(result.jobs_url, 'https://remaining-branches.example.com/openings');
      assert.equal(result.company_description, 'A company that builds great things.');
    });
  });
});

describe('MCP add_capture with explicit timing and text parameters', () => {
  it('covers captured_at ternary and selected_text OR branches', async () => {
    await withMcpClient(async client => {
      const result = parseToolResult(await client.callTool({
        name: 'add_capture',
        arguments: {
          url: 'https://example.com/captured-at-test',
          page_title: 'CapturedAt Test',
          selected_text: 'Explicitly selected text for this job posting',
          captured_at: '2026-05-01T10:00:00.000Z',
          schema_version: 2,
        },
      }));
      assert.equal(result.ok, true);
      assert.equal(result.duplicate, false);
    });
  });

  it('covers canonical_url, structured_data, user_note, source_browser, source_extension_version OR branches', async () => {
    await withMcpClient(async client => {
      const result = parseToolResult(await client.callTool({
        name: 'add_capture',
        arguments: {
          url: 'https://example.com/full-capture-test',
          page_title: 'Full Capture Test',
          visible_text: 'Senior engineer role full capture.',
          canonical_url: 'https://example.com/canonical/full-capture',
          structured_data: [{ '@type': 'JobPosting', title: 'Senior Engineer' }],
          user_note: 'Applied via referral',
          source_browser: 'Chrome',
          source_extension_version: '1.2.3',
        },
      }));
      assert.equal(result.ok, true);
    });
  });
});

describe('MCP add_site with various parameter combinations', () => {
  it('uses explicit origin field when provided', async () => {
    await withMcpClient(async client => {
      const result = parseToolResult(await client.callTool({
        name: 'add_site',
        arguments: {
          url: 'https://origin-explicit.example.com/jobs/index',
          origin: 'https://origin-explicit.example.com',
          interval_days: 7,
          note: 'Explicit origin test',
          state: 'reviewed',
        },
      }));
      assert.equal(result.origin, 'https://origin-explicit.example.com');
    });
  });

  it('handles invalid URL gracefully (normalizeSiteOrigin catch path)', async () => {
    await withMcpClient(async client => {
      const result = parseToolResult(await client.callTool({
        name: 'add_site',
        arguments: { url: 'not-a-valid-url-at-all' },
      }));
      assert.ok(result.id);
    });
  });
});

describe('MCP update_job error path', () => {
  it('throws when no fields are provided', async () => {
    await withMcpClient(async client => {
      await assert.rejects(
        () => client.callTool({ name: 'update_job', arguments: { job_id: 'some-id' } }),
        /field/i
      );
    });
  });
});

describe('MCP error paths', () => {
  it('add_capture throws when both visible_text and selected_text are missing', async () => {
    await withMcpClient(async client => {
      await assert.rejects(
        () => client.callTool({ name: 'add_capture', arguments: { url: 'https://example.com/no-text', page_title: 'No text' } }),
        /required/i
      );
    });
  });

  it('update_site returns error for nonexistent site', async () => {
    await withMcpClient(async client => {
      await assert.rejects(
        () => client.callTool({ name: 'update_site', arguments: { site_id: 'nonexistent-id', note: 'test' } }),
        /not found/i
      );
    });
  });

  it('update_site covers multiple optional field branches', async () => {
    await withMcpClient(async client => {
      const added = parseToolResult(await client.callTool({
        name: 'add_site',
        arguments: { url: 'https://multi-update.example.com/' },
      }));
      const siteId = added.id;
      // Cover multiple conditional update branches in updateSite
      const result = parseToolResult(await client.callTool({
        name: 'update_site',
        arguments: {
          site_id: siteId,
          note: 'Updated',
          interval_days: 7,
          state: 'reviewed',
          company_name: 'Multi Corp',
          company_website: 'https://multicorp.example.com',
        },
      }));
      assert.equal(result.company_name, 'Multi Corp');
      assert.equal(result.state, 'reviewed');
    });
  });
});

describe('MCP workflow_snapshot', () => {
  it('returns zero counts on an empty database', async () => {
    await withMcpClient(async client => {
      const snap = parseToolResult(await client.callTool({ name: 'workflow_snapshot', arguments: {} }));
      assert.equal(snap.jobs_total, 0);
      assert.equal(snap.sites_total, 0);
      assert.ok(typeof snap.sites_due === 'number');
      assert.ok(typeof snap.status_counts === 'object');
      assert.ok(typeof snap.extraction_status_counts === 'object');
    });
  });

  it('counts jobs and sites correctly after adding data', async () => {
    await withMcpClient(async client => {
      await client.callTool({ name: 'add_capture', arguments: { url: 'https://example.com/snap', page_title: 'Job', visible_text: 'Job desc text.' } });
      await client.callTool({ name: 'add_site', arguments: { url: 'https://jobs.example.com/' } });
      const snap = parseToolResult(await client.callTool({ name: 'workflow_snapshot', arguments: {} }));
      assert.equal(snap.jobs_total, 1);
      assert.equal(snap.sites_total, 1);
    });
  });
});
