import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { _releaseSupported, isAvailable, complete, shutdown } from '../../server/apple-foundation.js';

describe('_releaseSupported — Darwin release version check', () => {
  it('returns true for Darwin 25 (macOS 26 Tahoe)', () => {
    assert.equal(_releaseSupported('25.0.0'), true);
  });

  it('returns true for Darwin 26 (future macOS)', () => {
    assert.equal(_releaseSupported('26.1.0'), true);
  });

  it('returns false for Darwin 24 (macOS 15 Sequoia)', () => {
    assert.equal(_releaseSupported('24.5.0'), false);
  });

  it('returns false for Darwin 23 (macOS 14 Sonoma)', () => {
    assert.equal(_releaseSupported('23.0.0'), false);
  });

  it('handles release strings with only major version', () => {
    assert.equal(_releaseSupported('25'), true);
    assert.equal(_releaseSupported('24'), false);
  });
});

// Subprocess tests — only run when binary is available (macOS 26 with compiled binary).
// Skipped automatically on macOS < 26 or when binary is missing.
describe('apple-foundation subprocess', { skip: !isAvailable() }, () => {
  after(() => shutdown());

  it('complete() returns a non-empty string', async () => {
    const result = await complete({ prompt: 'Reply with only the word: hello', timeout: 60 });
    assert.equal(typeof result, 'string');
    assert.ok(result.trim().length > 0, 'response should be non-empty');
  }, { timeout: 65000 });

  it('complete() handles a second request on the same process', async () => {
    const result = await complete({ prompt: 'Reply with only the word: world', timeout: 60 });
    assert.equal(typeof result, 'string');
    assert.ok(result.trim().length > 0);
  }, { timeout: 65000 });

  it('complete() accepts a system prompt', async () => {
    const result = await complete({
      system: 'You are a calculator. Only output numbers.',
      prompt: 'What is 2 + 2?',
      timeout: 60,
    });
    assert.equal(typeof result, 'string');
    assert.ok(result.trim().length > 0);
  }, { timeout: 65000 });
});
