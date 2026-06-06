import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { selectFreeStructuredModels, runWithModelRotation, fetchFreeModelIds } from '../../server/extract.js';

describe('selectFreeStructuredModels', () => {
  const T = { input_modalities: ['text'], output_modalities: ['text'] };
  const data = {
    data: [
      { id: 'a/free-structured:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['structured_outputs', 'tools'], architecture: T },
      { id: 'b/free-response-format:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: { modality: 'text->text' } },
      { id: 'c/free-no-structured:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['tools'], architecture: T },
      { id: 'd/paid-structured', pricing: { prompt: '0.0000003', completion: '0.0000025' }, supported_parameters: ['structured_outputs'], architecture: T },
      { id: 'e/free-no-params:free', pricing: { prompt: '0', completion: '0' } },
      { id: 'f/free-audio:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: { input_modalities: ['text'], output_modalities: ['audio'] } },
      // Multimodal-input but text-only output → kept.
      { id: 'g/free-mm-input:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['structured_outputs'], architecture: { input_modalities: ['text', 'image'], output_modalities: ['text'] } },
      // Outputs text AND audio (e.g. Lyria) → excluded.
      { id: 'h/free-text-audio:free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: { output_modalities: ['text', 'audio'] } },
    ],
  };

  it('keeps only free text-output models that support structured output', () => {
    const ids = selectFreeStructuredModels(data);
    assert.deepEqual(ids.sort(), ['a/free-structured:free', 'b/free-response-format:free', 'g/free-mm-input:free']);
  });

  it('handles empty/malformed input', () => {
    assert.deepEqual(selectFreeStructuredModels(null), []);
    assert.deepEqual(selectFreeStructuredModels({}), []);
    assert.deepEqual(selectFreeStructuredModels({ data: [] }), []);
  });
});

describe('fetchFreeModelIds', () => {
  let originalFetch;

  before(() => {
    originalFetch = globalThis.fetch;
  });

  after(() => {
    globalThis.fetch = originalFetch;
  });

  const FREE_MODELS_RESPONSE = {
    data: [
      { id: 'free/a', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['structured_outputs'], architecture: { output_modalities: ['text'] } },
      { id: 'free/b', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: { modality: 'text->text' } },
      { id: 'paid/c', pricing: { prompt: '0.001', completion: '0.002' }, supported_parameters: ['structured_outputs'], architecture: { output_modalities: ['text'] } },
    ],
  };

  it('returns only free structured-output models', async () => {
    let capturedHeaders;
    globalThis.fetch = async (url, opts) => {
      capturedHeaders = opts?.headers || {};
      return { ok: true, json: async () => FREE_MODELS_RESPONSE };
    };
    const ids = await fetchFreeModelIds('');
    assert.deepEqual(ids.sort(), ['free/a', 'free/b']);
  });

  it('sends Authorization header when apiKey is provided', async () => {
    let capturedHeaders;
    globalThis.fetch = async (url, opts) => {
      capturedHeaders = opts?.headers || {};
      return { ok: true, json: async () => FREE_MODELS_RESPONSE };
    };
    await fetchFreeModelIds('sk-test-key');
    assert.equal(capturedHeaders['Authorization'], 'Bearer sk-test-key');
  });

  it('sends no Authorization header when apiKey is empty', async () => {
    let capturedHeaders;
    globalThis.fetch = async (url, opts) => {
      capturedHeaders = opts?.headers || {};
      return { ok: true, json: async () => FREE_MODELS_RESPONSE };
    };
    await fetchFreeModelIds('');
    assert.ok(!('Authorization' in capturedHeaders));
  });

  it('propagates HTTP errors as thrown exceptions', async () => {
    globalThis.fetch = async () => ({ ok: false, status: 401 });
    await assert.rejects(() => fetchFreeModelIds('bad-key'), /OpenRouter HTTP 401/);
  });

  it('propagates network errors as thrown exceptions', async () => {
    globalThis.fetch = async () => { throw new Error('ECONNREFUSED'); };
    await assert.rejects(() => fetchFreeModelIds(''), /ECONNREFUSED/);
  });
});

describe('runWithModelRotation', () => {
  it('uses the single model when the pool is empty', async () => {
    const calls = [];
    const out = await runWithModelRotation([], 'configured-model', async (m) => { calls.push(m); return 'ok'; });
    assert.equal(out, 'ok');
    assert.deepEqual(calls, ['configured-model']);
  });

  it('succeeds on the first model when it works', async () => {
    const pool = ['m1', 'm2', 'm3', 'm4', 'm5'];
    const calls = [];
    const out = await runWithModelRotation(pool, 'configured', async (m) => { calls.push(m); return 'good'; });
    assert.equal(out, 'good');
    assert.equal(calls.length, 1);
    assert.ok(pool.includes(calls[0]));
  });

  it('fails over to the next model on error', async () => {
    const pool = ['m1', 'm2', 'm3', 'm4', 'm5'];
    const calls = [];
    let n = 0;
    const out = await runWithModelRotation(pool, 'configured', async (m) => {
      calls.push(m);
      if (n++ < 2) throw new Error('429 overloaded');
      return 'recovered';
    });
    assert.equal(out, 'recovered');
    assert.equal(calls.length, 3); // failed twice, succeeded on third
    // distinct models tried (round-robin)
    assert.equal(new Set(calls).size, 3);
  });

  it('gives up after at most pool-length tries and rethrows', async () => {
    const pool = ['only1', 'only2'];
    const calls = [];
    await assert.rejects(
      runWithModelRotation(pool, 'configured', async (m) => { calls.push(m); throw new Error('always fails'); }),
      /always fails/,
    );
    assert.equal(calls.length, 2); // capped at pool length (< ROTATE_FAILOVER_TRIES)
  });
});
