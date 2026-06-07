import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { parseJdBlocks } from '../../static/jd-parser.js';

const LINKEDIN_JD = readFileSync(new URL('../fixtures/job-126-linkedin-pm.txt', import.meta.url), 'utf8');

// ----------------------------------------------------------------
// Basic structural tests
// ----------------------------------------------------------------

describe('parseJdBlocks — empty / null input', () => {
  it('returns empty array for empty string', () => {
    assert.deepEqual(parseJdBlocks(''), []);
  });

  it('returns empty array for null', () => {
    assert.deepEqual(parseJdBlocks(null), []);
  });
});

describe('parseJdBlocks — paragraphs', () => {
  it('produces a paragraph block for plain prose', () => {
    const blocks = parseJdBlocks('We are looking for an experienced engineer to join our team and build great products.');
    assert.equal(blocks.length, 1);
    assert.equal(blocks[0].type, 'paragraph');
  });

  it('merges consecutive non-empty lines into one paragraph', () => {
    const blocks = parseJdBlocks('Line one that is long enough to qualify.\nLine two continues the thought here.');
    const paras = blocks.filter(b => b.type === 'paragraph');
    assert.equal(paras.length, 1);
    assert.ok(paras[0].text.includes('Line one'));
    assert.ok(paras[0].text.includes('Line two'));
  });

  it('splits on blank lines into separate paragraphs', () => {
    const text = 'First paragraph is long enough to be included.\n\nSecond paragraph also qualifies here.';
    const paras = parseJdBlocks(text).filter(b => b.type === 'paragraph');
    assert.equal(paras.length, 2);
  });
});

describe('parseJdBlocks — headings', () => {
  it('detects ALL-CAPS line as heading', () => {
    const blocks = parseJdBlocks('We are hiring a great engineer.\n\nREQUIREMENTS\n\nSome requirement here.');
    const heading = blocks.find(b => b.type === 'heading');
    assert.ok(heading, 'expected a heading block');
    assert.equal(heading.text, 'REQUIREMENTS');
  });

  it('detects line ending in colon as heading', () => {
    const blocks = parseJdBlocks('We are hiring.\n\nWhat you will do:\n\nLead the team.');
    const heading = blocks.find(b => b.type === 'heading');
    assert.ok(heading);
    assert.equal(heading.text, 'What you will do');
  });

  it('detects known keyword line as heading', () => {
    const blocks = parseJdBlocks('We are hiring.\n\nResponsibilities\n\nLead the team.');
    const heading = blocks.find(b => b.type === 'heading');
    assert.ok(heading);
  });
});

describe('parseJdBlocks — lists', () => {
  it('detects bullet lines starting with •', () => {
    const blocks = parseJdBlocks('Requirements:\n• Five years experience\n• Strong communication');
    const list = blocks.find(b => b.type === 'list');
    assert.ok(list);
    assert.equal(list.items.length, 2);
    assert.equal(list.items[0], 'Five years experience');
  });

  it('detects bullet lines starting with -', () => {
    const blocks = parseJdBlocks('Skills:\n- Python\n- SQL');
    const list = blocks.find(b => b.type === 'list');
    assert.ok(list);
    assert.equal(list.items.length, 2);
  });

  it('detects numbered list items', () => {
    const blocks = parseJdBlocks('Steps:\n1. Do this first\n2. Then do this');
    const list = blocks.find(b => b.type === 'list');
    assert.ok(list);
    assert.equal(list.items[0], 'Do this first');
  });
});

// ----------------------------------------------------------------
// LinkedIn-specific regression: job-126
// ----------------------------------------------------------------

describe('parseJdBlocks — LinkedIn job-126 regression', () => {
  it('skips LinkedIn profile chrome before the actual post', () => {
    const blocks = parseJdBlocks(LINKEDIN_JD);
    // The very first block should not be the user's own profile headline
    const firstText = blocks[0]?.text || blocks[0]?.text || '';
    assert.ok(
      !firstText.includes('Technical Program Manager @ Meta'),
      `First block should not be the user profile header, got: "${firstText.slice(0, 80)}"`
    );
  });

  it('includes the actual job title as a heading or first content', () => {
    const blocks = parseJdBlocks(LINKEDIN_JD);
    const allText = blocks.map(b => b.text || b.items?.join(' ') || '').join(' ');
    assert.ok(allText.includes('Technical Product Manager'), 'job title should appear in parsed content');
  });

  it('strips the concatenated duplicate paragraph at the bottom', () => {
    const blocks = parseJdBlocks(LINKEDIN_JD);
    const allText = blocks.map(b => b.text || '').join('\n');
    assert.ok(
      !allText.includes('Feed postIT Recruiter'),
      'concatenated LinkedIn duplicate should be stripped'
    );
  });

  it('does not end with a bare hr block', () => {
    const blocks = parseJdBlocks(LINKEDIN_JD);
    assert.notEqual(blocks[blocks.length - 1]?.type, 'hr', 'trailing hr should be removed');
  });

  it('includes job requirements as list items', () => {
    const blocks = parseJdBlocks(LINKEDIN_JD);
    const lists = blocks.filter(b => b.type === 'list');
    const allItems = lists.flatMap(l => l.items);
    assert.ok(allItems.some(i => i.includes('years')), 'requirements list items should be present');
  });
});
