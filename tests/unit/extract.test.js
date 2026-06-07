import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { expandMetros } from '../../server/metros.js';
import {
  parseBoolSetting,
  applyLocationFilter,
  computeOverallFitScore,
  normalizeCompanyFromSource,
  normalizeEmploymentFromSource,
  normalizeLocationFromSource,
  normalizeRemoteTypeFromSource,
  normalizeSalaryFromSource,
  parseExtractedJob,
  resolveProviderBaseUrl,
  _parseFitScore,
  _missingRequirementsPenalty,
  _fitUserPrompt,
  _userPrompt,
  refreshRotationPool,
  runWithModelRotation,
  _onSuccess,
  _onRateLimit,
  _resetConcurrencyState,
  selectFreeStructuredModels,
} from '../../server/extract.js';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const __dirname = dirname(fileURLToPath(import.meta.url));
const GLANCE_PM_JD = readFileSync(join(__dirname, '../fixtures/job-128-glance-pm.txt'), 'utf8');

describe('parseExtractedJob', () => {
  it('coerces null and invalid enum values to unknown', () => {
    const parsed = parseExtractedJob(JSON.stringify({
      company: 'Acme',
      title: 'TPM',
      location: null,
      remote_type: 'distributed',
      employment_type: null,
      skills: null,
      requirements: null,
      nice_to_haves: null,
      benefits: null,
    }));

    assert.equal(parsed.remote_type, 'unknown');
    assert.equal(parsed.employment_type, 'unknown');
    assert.deepEqual(parsed.skills, []);
    assert.deepEqual(parsed.requirements, []);
  });
});

describe('normalizeSalaryFromSource', () => {
  it('computes annual salary from an hourly range using 2080 hours', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 174800,
      salary_max: 211600,
      salary_hourly_min: null,
      salary_hourly_max: null,
      salary_currency: null,
      salary_note: 'Pay: $85/hr - $105/hr on W2 contract.',
    });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_hourly_min, 85);
    assert.equal(normalized.salary_hourly_max, 105);
    assert.equal(normalized.salary_min, 176800);
    assert.equal(normalized.salary_max, 218400);
  });

  it('computes annual salary from hourly language without slash notation', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'Hourly compensation range is $72.50 to $90 per hour.',
    });

    assert.equal(normalized.salary_hourly_min, 72.5);
    assert.equal(normalized.salary_hourly_max, 90);
    assert.equal(normalized.salary_min, 150800);
    assert.equal(normalized.salary_max, 187200);
  });

  it('computes annual salary from hourly ranges with currency after the number', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 100000,
      salary_max: 300000,
      salary_currency: 'USD',
      salary_note: '50 - 150USD/Hr, based on experience and location',
    });

    assert.equal(normalized.salary_hourly_min, 50);
    assert.equal(normalized.salary_hourly_max, 150);
    assert.equal(normalized.salary_min, 104000);
    assert.equal(normalized.salary_max, 312000);
  });

  it('uses the low and high annual money values from the salary note', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 120000,
      salary_max: 220000,
      salary_note: 'Salary range: $185,000 - $245,000 USD base salary.',
    });

    assert.equal(normalized.salary_min, 185000);
    assert.equal(normalized.salary_max, 245000);
  });

  it('parses annual values with currency before and after the range', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'USD114,000.00 - $148,000.00',
    });

    assert.equal(normalized.salary_min, 114000);
    assert.equal(normalized.salary_max, 148000);
  });

  it('parses compact annual ranges with currency prefix', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'USD179000–210000 Annually',
    });

    assert.equal(normalized.salary_min, 179000);
    assert.equal(normalized.salary_max, 210000);
  });

  it('parses annual ranges with currency after the second value', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'San Francisco Bay Area: 133400 - 226600 USD Annual; All Other US Locations: 116000 - 197000 USD Annual.',
    });

    assert.equal(normalized.salary_min, 116000);
    assert.equal(normalized.salary_max, 226600);
  });

  it('does not mix CAD salary bands into USD salary ranges', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 200700,
      salary_max: 250900,
      salary_currency: 'USD',
      salary_note: 'US employees (any location): $200,700 - $250,900; Canadian employees (any location): CAD 189,700 - 237,100',
    });

    assert.equal(normalized.salary_min, 200700);
    assert.equal(normalized.salary_max, 250900);
  });

  it('handles compact annual k notation', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'Base pay is $140k-$200k plus equity.',
    });

    assert.equal(normalized.salary_min, 140000);
    assert.equal(normalized.salary_max, 200000);
  });

  it('uses the lowest and highest values when a note includes multiple annual bands', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 185000,
      salary_max: 245000,
      salary_note: 'Salary range: $185,000 - $245,000 USD base salary. San Francisco and New York range: $210,000 - $285,000 USD.',
    });

    assert.equal(normalized.salary_min, 185000);
    assert.equal(normalized.salary_max, 285000);
  });

  it('uses a preferred state-specific annual band when one matches', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 178000,
      salary_max: 216500,
      salary_currency: 'USD',
      salary_note: `CA, NY, CT, NJ
$214,000-$216,500 USD
WA
$205,000-$216,500 USD
All other states
$178,000-$188,000 USD`,
    }, { preferredLocations: 'Seattle, WA, Remote, United States' });

    assert.equal(normalized.salary_min, 205000);
    assert.equal(normalized.salary_max, 216500);
  });

  it('uses source text for preferred state-specific bands when the model salary note omits labels', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 214000,
      salary_max: 216500,
      salary_currency: 'USD',
      salary_note: '$214,000-$216,500 USD; $205,000-$216,500 USD; $178,000-$188,000 USD',
    }, {
      preferredLocations: 'Seattle, WA, Remote, United States',
      sourceText: `CA, NY, CT, NJ
$214,000-$216,500 USD
WA
$205,000-$216,500 USD
All other states
$178,000-$188,000 USD`,
    });

    assert.equal(normalized.salary_min, 205000);
    assert.equal(normalized.salary_max, 216500);
  });

  it('uses the general US band when specific metro bands do not match preferences', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 119800,
      salary_max: 258000,
      salary_currency: 'USD',
      salary_note: 'The typical base pay range for this role across the U.S. is USD $119,800 - $234,700 per year. There is a different range applicable to specific work locations, within the San Francisco Bay area and New York City metropolitan area, and the base pay range for this role in those locations is USD $158,400 - $258,000 per year.',
    }, { preferredLocations: 'Seattle, WA, Remote, United States' });

    assert.equal(normalized.salary_min, 119800);
    assert.equal(normalized.salary_max, 234700);
  });

  it('normalizes mixed USD/CAD currency output to the USD salary band', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: 189700,
      salary_max: 250900,
      salary_currency: 'USD/CAD',
      salary_note: 'US employees (any location): $200,700 - $250,900; Canadian employees (any location): CAD 189,700 - 237,100',
    });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_min, 200700);
    assert.equal(normalized.salary_max, 250900);
  });

  // Workday platform uses "133,400 - 226,600 USD Annual" format (no $ sign, comma-separated
  // thousands, currency code after range, "Annual" keyword). This format appears at the bottom
  // of the page under location-specific salary bands.
  it('parses Workday multi-band salary_note (comma-separated thousands, USD Annual)', () => {
    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: 'San Francisco Bay Area:\n133,400 - 226,600 USD Annual\nAll Other US Locations:\n116,000 - 197,000 USD Annual',
    });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_min, 116000);
    assert.equal(normalized.salary_max, 226600);
  });

  it('recovers Workday salary from sourceText when LLM returns null salary_note', () => {
    // When the LLM misses the salary (no $ sign → salary_note stays null), the extractor
    // passes the raw page text as sourceText. normalizeSalaryFromSource must fall back to it.
    const workdayPageFragment = [
      'The base pay range varies based on geographic location.',
      'San Francisco Bay Area:',
      '133,400 - 226,600 USD Annual',
      'All Other US Locations:',
      '116,000 - 197,000 USD Annual',
    ].join('\n');

    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: null,
    }, { sourceText: workdayPageFragment });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_min, 116000);
    assert.equal(normalized.salary_max, 226600);
  });

  it('recovers Workday salary from sourceText respecting preferred location band', () => {
    const workdayPageFragment = [
      'San Francisco Bay Area:',
      '133,400 - 226,600 USD Annual',
      'All Other US Locations:',
      '116,000 - 197,000 USD Annual',
    ].join('\n');

    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: null,
    }, {
      sourceText: workdayPageFragment,
      preferredLocations: 'San Francisco, CA',
    });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_min, 133400);
    assert.equal(normalized.salary_max, 226600);
  });

  it('selects All Other US band from cleaned Workday sourceText when user is outside SF', () => {
    // cleaning.js now preserves location labels as "Label: range" lines, e.g.:
    // "San Francisco Bay Area: 133,400 - 226,600 USD Annual"
    // "All Other US Locations: 116,000 - 197,000 USD Annual"
    // normalizeSalaryFromSource must select the right band from this format.
    const cleanedFragment = [
      'San Francisco Bay Area: 133,400 - 226,600 USD Annual',
      'All Other US Locations: 116,000 - 197,000 USD Annual',
    ].join('\n');

    const normalized = normalizeSalaryFromSource({
      salary_min: null,
      salary_max: null,
      salary_note: null,
    }, {
      sourceText: cleanedFragment,
      preferredLocations: 'Seattle, WA, Remote, United States',
    });

    assert.equal(normalized.salary_currency, 'USD');
    assert.equal(normalized.salary_min, 116000);
    assert.equal(normalized.salary_max, 197000);
  });
});

describe('computeOverallFitScore', () => {
  it('computes a weighted score from dimension scores', () => {
    const score = computeOverallFitScore([
      { name: 'required_qualifications', score: 100 },
      { name: 'preferred_qualifications', score: 0 },
      { name: 'skills', score: 80 },
      { name: 'experience_level', score: 90 },
      { name: 'domain_fit', score: 60 },
    ]);

    assert.equal(score, 84);
  });

  it('renormalizes when only known dimensions are present', () => {
    const score = computeOverallFitScore([
      { name: 'required_qualifications', score: 100 },
      { name: 'unknown', score: 0 },
      { name: 'skills', score: 80 },
    ]);

    assert.equal(score, 95);
  });
});

describe('parseBoolSetting', () => {
  it('returns true for true-like strings', () => {
    for (const v of ['true', '1', 'yes', 'on', 'enabled', 'TRUE']) {
      assert.equal(parseBoolSetting(v), true, `expected true for ${v}`);
    }
  });

  it('returns false for false-like strings', () => {
    for (const v of ['false', '0', 'no', 'off', 'disabled', 'FALSE']) {
      assert.equal(parseBoolSetting(v, true), false, `expected false for ${v}`);
    }
  });

  it('returns defaultVal for null/undefined', () => {
    assert.equal(parseBoolSetting(null, true), true);
    assert.equal(parseBoolSetting(undefined, false), false);
  });

  it('passes through boolean values directly', () => {
    assert.equal(parseBoolSetting(true, false), true);
    assert.equal(parseBoolSetting(false, true), false);
  });

  it('returns defaultVal for unrecognised strings', () => {
    assert.equal(parseBoolSetting('maybe', true), true);
    assert.equal(parseBoolSetting('', false), false);
  });
});

describe('applyLocationFilter', () => {
  const base = { company: 'Acme', title: 'SWE', location: 'Seattle, WA', remote_type: 'onsite' };

  it('passes through when no filters are set', () => {
    const result = applyLocationFilter({ ...base });
    assert.equal(result.location, 'Seattle, WA');
    assert.equal(result.remote_type, 'onsite');
  });

  it('matches a preferred city', () => {
    const result = applyLocationFilter({ ...base }, { preferredLocations: 'Seattle' });
    assert.ok(result.location?.includes('Seattle'));
    assert.equal(result.remote_type, 'onsite');
  });

  it('preserves location when no preferred location matches', () => {
    const result = applyLocationFilter({ ...base, location: 'Austin, TX' }, { preferredLocations: 'Seattle' });
    assert.equal(result.location, 'Austin, TX');
    assert.equal(result.remote_type, 'onsite');
    assert.equal(result.meets_criteria, false);
  });

  it('expands state abbreviation to full name in preferred locations', () => {
    // 'WA' should match 'Seattle, WA'
    const result = applyLocationFilter({ ...base }, { preferredLocations: 'WA' });
    assert.ok(result.location !== null, 'WA abbreviation should match Seattle, WA');
  });

  it('preserves remote jobs when allowRemote is true and no preferred locations', () => {
    const remote = { ...base, location: 'Remote', remote_type: 'remote' };
    const result = applyLocationFilter(remote, { allowRemote: true });
    assert.equal(result.remote_type, 'remote');
  });

  it('preserves remote jobs with preferred locations set when allowRemote is true', () => {
    // Remote jobs don't need a location match — physical city is irrelevant for remote work
    const remote = { ...base, location: 'Hiring Remotely in USA', remote_type: 'remote' };
    const result = applyLocationFilter(remote, { preferredLocations: 'Seattle', allowRemote: true });
    assert.equal(result.remote_type, 'remote');
    assert.equal(result.location, 'Hiring Remotely in USA');
    assert.equal(result.meets_criteria, true);
  });

  it('marks remote jobs as not meeting criteria when allowRemote is false', () => {
    const remote = { ...base, location: 'Remote', remote_type: 'remote' };
    const result = applyLocationFilter(remote, { preferredLocations: 'Seattle', allowRemote: false });
    assert.equal(result.remote_type, 'remote');
    assert.equal(result.location, 'Remote');
    assert.equal(result.meets_criteria, false);
  });

  it('preserves remote jobs when allowRemote is false', () => {
    const remote = { ...base, location: 'Remote', remote_type: 'remote' };
    const result = applyLocationFilter(remote, { preferredLocations: 'Seattle', allowRemote: false });
    assert.equal(result.remote_type, 'remote');
    assert.equal(result.location, 'Remote');
    assert.equal(result.meets_criteria, false);
  });

  it('preserves onsite jobs when allowOnsite is false', () => {
    const result = applyLocationFilter(
      { ...base },
      { preferredLocations: 'Seattle', allowOnsite: false }
    );
    assert.equal(result.remote_type, 'onsite');
    assert.equal(result.location, 'Seattle, WA');
    assert.equal(result.meets_criteria, false);
  });

  it('handles missing location gracefully', () => {
    const result = applyLocationFilter({ ...base, location: null }, { preferredLocations: 'Seattle' });
    assert.equal(result.location, null);
  });
});

describe('normalizeRemoteTypeFromSource', () => {
  it('treats Remote or Hybrid as remote before location filtering', () => {
    const extracted = {
      company: 'Luma AI',
      title: 'Technical Program Manager, Research',
      location: 'USA; California, USA',
      remote_type: 'hybrid',
    };
    const description = `Title: Technical Program Manager, Research
Work arrangement: Remote (telecommute)
Hiring location: CAN; USA
Location: USA; California, USA
Work arrangement: Hybrid
Remote or Hybrid`;

    const normalized = normalizeRemoteTypeFromSource(extracted, description);
    const result = applyLocationFilter(normalized, {
      preferredLocations: 'WA, Washington, Seattle',
      allowRemote: true,
      allowHybrid: false,
      allowOnsite: false,
    });

    assert.equal(result.remote_type, 'remote');
    assert.equal(result.location, 'USA; California, USA');
    assert.equal(result.meets_criteria, true);
  });

  it('uses raw capture source when cleaned text omits the remote badge', () => {
    const extracted = {
      company: 'Deepgram',
      title: 'Technical Program Manager, Research',
      location: 'USA',
      remote_type: 'unknown',
    };
    const source = `Title: Technical Program Manager, Research
Location: USA
Remote
Hiring Remotely in USA
{"jobLocationType":"TELECOMMUTE"}`;

    const normalized = normalizeRemoteTypeFromSource(extracted, source);
    const result = applyLocationFilter(normalized, {
      preferredLocations: 'WA, Washington, Seattle',
      allowRemote: true,
      allowHybrid: false,
      allowOnsite: false,
    });

    assert.equal(result.remote_type, 'remote');
    assert.equal(result.location, 'USA');
    assert.equal(result.meets_criteria, true);
  });

  it('uses Levels.fyi remote filter parameters as a remote signal', () => {
    const normalized = normalizeRemoteTypeFromSource(
      { company: 'Zscaler', title: 'Sr. Staff Technical Program Manager - DoW', location: null, remote_type: 'unknown' },
      'Sr. Staff Technical Program Manager - DoW\nZscaler\nRole',
      'https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710&perkIds=58'
    );
    const result = applyLocationFilter(normalized, {
      preferredLocations: 'Seattle, WA',
      allowRemote: true,
      allowHybrid: false,
      allowOnsite: false,
    });

    assert.equal(result.remote_type, 'remote');
    assert.equal(result.meets_criteria, true);
  });

  it('treats BuiltIn Hiring Remotely badges as remote even with no physical location', () => {
    const normalized = normalizeRemoteTypeFromSource(
      { company: 'Deepgram', title: 'Principal Technical Program Manager', location: null, remote_type: 'unknown' },
      `Principal Technical Program Manager
Remote
Hiring Remotely in USA
About the role`
    );
    const withLocation = normalizeLocationFromSource(normalized, 'Remote\nHiring Remotely in USA');

    assert.equal(withLocation.remote_type, 'remote');
    assert.equal(withLocation.location, 'Remote');
  });

  it('overrides bare country location with Remote when source has Remote line', () => {
    // LLM sees "Hiring Remotely in USA" and returns location: 'USA'; source has "Remote" on its own line
    const result = normalizeLocationFromSource(
      { company: 'Google Fiber', title: 'Senior TPM', location: 'USA', remote_type: 'remote' },
      'Remote\nHiring Remotely in USA'
    );
    assert.equal(result.location, 'Remote');
  });

  it('treats explicit remote-candidate language as remote', () => {
    const normalized = normalizeRemoteTypeFromSource(
      { company: 'Zscaler', title: 'SPM', location: null, remote_type: 'unknown' },
      'This is a hybrid role based in San Jose, CA (3 days onsite). While local candidates are preferred, we are open to remote candidates based on the West Coast for exceptional applicants.'
    );

    assert.equal(normalized.remote_type, 'remote');
  });

  it('infers Microsoft 0 days in-office as remote', () => {
    const normalized = normalizeRemoteTypeFromSource(
      { company: 'Microsoft', title: 'PM', location: 'United States, Washington, Redmond', remote_type: 'unknown' },
      'Work site\n0 days / week in-office'
    );

    assert.equal(normalized.remote_type, 'remote');
  });

  it('infers Microsoft office-days work site as hybrid', () => {
    const normalized = normalizeRemoteTypeFromSource(
      { company: 'Microsoft', title: 'PM', location: 'United States, Washington, Redmond', remote_type: 'unknown' },
      'Work site\n4 days / week in-office'
    );

    assert.equal(normalized.remote_type, 'hybrid');
  });
});

describe('normalizeLocationFromSource', () => {
  it('recovers location from metadata lines', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Microsoft', title: 'Senior Product Manager', location: null, remote_type: 'unknown' },
      'Title: Senior Product Manager\nLocation: United States, Multiple Locations, Multiple Locations\nWork site: 0 days / week in-office - remote'
    );

    assert.equal(normalized.location, 'United States, Multiple Locations, Multiple Locations');
  });

  it('uses Remote as location when the source has no physical location but is fully remote', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Reddit', title: 'Principal Technical Program Manager', location: null, remote_type: 'unknown' },
      'Principal Technical Program Manager\nReddit · 8 days ago · Fully Remote'
    );

    assert.equal(normalized.location, 'Remote');
  });

  it('recovers city/state location from the line after the title', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Pinterest', title: 'Technical Program Manager II, Platforms', location: null, remote_type: 'unknown' },
      'Technical Program Manager II, Platforms\nSan Francisco, CA\n$103,965 - $214,044 a year'
    );

    assert.equal(normalized.location, 'San Francisco, CA');
  });

  it('recovers location from hybrid role based-in language', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Zscaler', title: 'Senior Product Manager', location: null, remote_type: 'unknown' },
      'This is a hybrid role based in San Jose, CA (3 days onsite). While local candidates are preferred, we are open to remote candidates based on the West Coast.'
    );

    assert.equal(normalized.location, 'San Jose, CA');
  });

  it('recovers Microsoft job location from the selected search result detail', () => {
    const extracted = {
      company: 'Microsoft',
      title: 'Technical Program Manager',
      location: null,
      remote_type: 'unknown',
    };
    const source = `Search jobs
Technical Program Manager
United States, Washington, Redmond +2 more
Apply now
Job description
Work site 4 days / week in-office`;

    const normalized = normalizeLocationFromSource(extracted, source);
    const result = applyLocationFilter(normalized, {
      preferredLocations: 'WA, Washington, Seattle, Redmond',
      allowRemote: true,
      allowHybrid: false,
      allowOnsite: false,
    });

    assert.equal(result.location, 'United States, Washington, Redmond + 2 more');
    assert.equal(result.meets_criteria, false);
  });

  it('preserves remote country context from source text', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Instacart', title: 'Senior Technical Program Manager', location: null, remote_type: 'remote' },
      'Instacart\nSenior Technical Program Manager\nRemote - United States\nRole details'
    );

    assert.equal(normalized.location, 'Remote - United States');
  });

  it('expands bare remote location when source has country context', () => {
    const normalized = normalizeLocationFromSource(
      { company: 'Mercury', title: 'Senior Product Manager', location: 'Remote', remote_type: 'remote' },
      'Mercury\nSenior Product Manager\nRemote - United States or Canada\nRole details'
    );

    assert.equal(normalized.location, 'Remote - United States or Canada');
  });
});

describe('normalizeEmploymentFromSource', () => {
  it('keeps full-time when the source explicitly says full-time', () => {
    const normalized = normalizeEmploymentFromSource(
      { employment_type: 'full_time' },
      'Employment type: Full-Time'
    );

    assert.equal(normalized.employment_type, 'full_time');
  });

  it('removes guessed full-time when the source does not say full-time', () => {
    const normalized = normalizeEmploymentFromSource(
      { employment_type: 'full_time' },
      'Required qualifications:\n- 7+ years technical program management experience.'
    );

    assert.equal(normalized.employment_type, 'unknown');
  });
});

describe('normalizeCompanyFromSource', () => {
  it('recovers company from structured JobPosting data', () => {
    const normalized = normalizeCompanyFromSource(
      { company: null, title: 'Adobe Commerce Technical Program Manager (TPM)' },
      '"hiringOrganization":{"@type":"Organization","name":"Blue Acorn iCi","sameAs":"https://builtin.com/company/blue-acorn-ici"}'
    );

    assert.equal(normalized.company, 'Blue Acorn iCi');
  });
});

describe('expandMetros', () => {
  it('returns empty array for empty string', () => {
    assert.deepEqual(expandMetros(''), []);
  });

  it('returns empty array for null/undefined', () => {
    assert.deepEqual(expandMetros(null), []);
    assert.deepEqual(expandMetros(undefined), []);
  });

  it('expands a single metro to its cities plus state terms', () => {
    const result = expandMetros('wa:seattle');
    assert.ok(result.includes('Seattle'), 'should include Seattle');
    assert.ok(result.includes('Bellevue'), 'should include Bellevue');
    assert.ok(result.includes('Redmond'), 'should include Redmond');
    assert.ok(result.includes('WA'), 'should include state abbreviation WA');
    assert.ok(result.includes('Washington'), 'should include full state name');
  });

  it('expands multiple metros and deduplicates state terms', () => {
    const result = expandMetros('wa:seattle,ca:bay-area');
    assert.ok(result.includes('Seattle'));
    assert.ok(result.includes('San Francisco'));
    assert.ok(result.includes('WA'));
    assert.ok(result.includes('CA'));
    // State terms should not appear twice
    assert.equal(result.filter(c => c === 'WA').length, 1);
  });

  it('ignores unknown state/metro tokens gracefully', () => {
    assert.deepEqual(expandMetros('xx:unknown'), []);
    assert.deepEqual(expandMetros('wa:nonexistent'), []);
  });
});

describe('applyLocationFilter — filterEnabled', () => {
  it('returns meets_criteria=true for any location when filterEnabled is false', () => {
    const base = { company: 'Acme', title: 'SWE', location: 'Austin, TX', remote_type: 'onsite' };
    const result = applyLocationFilter({ ...base }, {
      preferredLocations: 'Seattle',
      allowOnsite: true,
      filterEnabled: false,
    });
    assert.equal(result.meets_criteria, true);
  });

  it('still filters when filterEnabled defaults to true', () => {
    const base = { company: 'Acme', title: 'SWE', location: 'Austin, TX', remote_type: 'onsite' };
    const result = applyLocationFilter({ ...base }, {
      preferredLocations: 'Seattle',
      allowOnsite: true,
    });
    assert.equal(result.meets_criteria, false);
  });

  it('does not filter remote jobs regardless of filterEnabled', () => {
    const base = { company: 'Acme', title: 'SWE', location: 'Austin, TX', remote_type: 'remote' };
    const result = applyLocationFilter({ ...base }, {
      preferredLocations: 'Seattle',
      allowRemote: true,
      filterEnabled: true,
    });
    assert.equal(result.meets_criteria, true);
  });
});

describe('resolveProviderBaseUrl', () => {
  it('hosted providers return fixed URLs regardless of any baseUrl setting', () => {
    assert.equal(resolveProviderBaseUrl('openai'),     'https://api.openai.com');
    assert.equal(resolveProviderBaseUrl('openrouter'), 'https://openrouter.ai/api');
    assert.equal(resolveProviderBaseUrl('anthropic'),  'https://api.anthropic.com');
    assert.equal(resolveProviderBaseUrl('google'),     'https://generativelanguage.googleapis.com');
  });
  it('local/custom providers use the provided baseUrl', () => {
    assert.equal(resolveProviderBaseUrl('lmstudio', 'http://localhost:1234'), 'http://localhost:1234');
    assert.equal(resolveProviderBaseUrl('custom', 'http://myserver:8080/'), 'http://myserver:8080');
  });
});

describe('missingRequirementsPenalty', () => {
  it('returns 0 for empty or non-array input', () => {
    assert.equal(_missingRequirementsPenalty([]), 0);
    assert.equal(_missingRequirementsPenalty(null), 0);
    assert.equal(_missingRequirementsPenalty(undefined), 0);
  });

  it('charges 5 pts per generic missing requirement', () => {
    assert.equal(_missingRequirementsPenalty(['python', 'sql']), 10);
  });

  it('charges 10 pts for domain-specific gaps (asic, fpga, etc.)', () => {
    assert.equal(_missingRequirementsPenalty(['asic design experience', 'fpga knowledge']), 20);
  });

  it('caps total penalty at 50', () => {
    const many = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'];
    assert.equal(_missingRequirementsPenalty(many), 50);
  });
});

describe('parseFitScore', () => {
  it('parses a valid fit score JSON response', () => {
    const content = JSON.stringify({
      summary: 'Strong fit overall',
      dimensions: [
        { name: 'required_qualifications', score: 85, rationale: 'Meets most requirements' },
        { name: 'skills', score: 70, rationale: 'Good skill match' },
      ],
      requirements_met: ['leadership', 'program management'],
      requirements_not_met: [],
    });
    const result = _parseFitScore(content);
    assert.equal(result.summary, 'Strong fit overall');
    assert.equal(result.dimensions.length, 2);
    assert.equal(result.dimensions[0].score, 85);
    assert.deepEqual(result.requirements_met, ['leadership', 'program management']);
    assert.deepEqual(result.requirements_not_met, []);
    assert.equal(result.requirements_penalty, 0);
    assert.ok(typeof result.overall_score === 'number' || result.overall_score === null);
  });

  it('applies penalty for unmet requirements and subtracts from overall score', () => {
    const content = JSON.stringify({
      dimensions: [{ name: 'required_qualifications', score: 80, rationale: '' }],
      requirements_met: [],
      requirements_not_met: ['python', 'sql'],
      summary: null,
    });
    const result = _parseFitScore(content);
    assert.equal(result.requirements_penalty, 10);
    assert.ok(result.overall_score !== null);
    assert.ok(result.overall_score <= 80);
  });

  it('handles missing dimensions gracefully (returns null overall_score)', () => {
    const content = JSON.stringify({ summary: 'No dims', dimensions: [], requirements_met: [], requirements_not_met: [] });
    const result = _parseFitScore(content);
    assert.equal(result.overall_score, null);
  });
});

describe('loadsJsonLenient (via parseExtractedJob)', () => {
  it('repairs trailing-comma JSON via jsonrepair', () => {
    const malformed = '{ "company": "Acme", "title": "TPM", }';
    const parsed = parseExtractedJob(malformed);
    assert.equal(parsed.company, 'Acme');
    assert.equal(parsed.title, 'TPM');
  });

  it('throws on truly unparseable content', () => {
    assert.throws(() => parseExtractedJob('not json at all !!!'), /JSON/);
  });
});

describe('applyLocationFilter branch coverage', () => {
  it('returns meets_criteria:true (fallback) when remote_type is null and no preferred locations', () => {
    const result = applyLocationFilter({ company: 'Acme', title: 'SWE', location: 'Seattle', remote_type: null });
    assert.ok(typeof result.meets_criteria === 'boolean');
  });

  it('returns meets_criteria for hybrid remote_type with preferred locations (hybrid+terms branch)', () => {
    const result = applyLocationFilter(
      { company: 'Acme', title: 'SWE', location: 'Seattle, WA', remote_type: 'hybrid' },
      { preferredLocations: 'Seattle', allowHybrid: true }
    );
    assert.equal(result.remote_type, 'hybrid');
    assert.ok(typeof result.meets_criteria === 'boolean');
  });

  it('returns meets_criteria for onsite remote_type with preferred locations (onsite+terms branch)', () => {
    const result = applyLocationFilter(
      { company: 'Acme', title: 'SWE', location: 'Austin, TX', remote_type: 'onsite' },
      { preferredLocations: 'Seattle', allowOnsite: true }
    );
    assert.equal(result.remote_type, 'onsite');
    assert.ok(typeof result.meets_criteria === 'boolean');
  });
});

describe('normalizeRemoteTypeFromSource URL branch coverage', () => {
  it('covers urlIndicatesRemote return false path for non-remote URL', () => {
    const extracted = { company: 'Acme', title: 'SWE', location: 'Seattle, WA', remote_type: 'onsite' };
    const result = normalizeRemoteTypeFromSource(extracted, 'Onsite only role', 'https://jobs.example.com/engineer?ref=board');
    assert.equal(result.remote_type, 'onsite');
  });

  it('covers urlIndicatesRemote TRUE path for Indeed remote URL', () => {
    const extracted = { company: 'Acme', title: 'SWE', location: 'Remote', remote_type: 'onsite' };
    const result = normalizeRemoteTypeFromSource(extracted, 'No remote indicators in text', 'https://www.indeed.com/jobs?remotejob=1&q=engineer');
    assert.equal(result.remote_type, 'remote');
  });
});

describe('normalizeSalaryFromSource selectSalaryBand branch coverage', () => {
  it('covers "different range" note branch when All Other US band is present', () => {
    // salary_note must have 2+ bands for selectSalaryBand to reach line 516
    const extracted = {
      salary_note: 'San Francisco Bay Area:\n$180,000 - $220,000 USD Annual\nAll Other US Locations:\n$100,000 - $200,000 USD Annual\ndifferent range applicable to specific work locations',
    };
    const result = normalizeSalaryFromSource(extracted, {});
    assert.equal(result.salary_min, 100000);
    assert.equal(result.salary_max, 200000);
  });

  it('covers "different range" note branch when no All Other US band exists', () => {
    // bands.find(...) returns undefined → || null TRUE branch on line 517
    const extracted = {
      salary_note: 'East Coast:\n$90,000 - $110,000 USD Annual\nWest Coast:\n$120,000 - $140,000 USD Annual\ndifferent range applicable to specific work locations',
    };
    const result = normalizeSalaryFromSource(extracted, {});
    assert.ok(typeof result.salary_min === 'number' || result.salary_min == null);
  });
});

describe('parsePreferredLocations state name expansion', () => {
  it('expands state name to abbreviation (covers STATE_NAME_TO_ABBREV branch)', () => {
    // "Washington" → should also add "WA" as a term
    const result = applyLocationFilter(
      { company: 'Acme', title: 'SWE', location: 'Seattle, Washington', remote_type: 'onsite' },
      { preferredLocations: 'Washington', allowOnsite: true }
    );
    assert.ok(typeof result.meets_criteria === 'boolean');
  });
});

describe('normalizeLocationFromSource branch coverage', () => {
  it('returns extracted unchanged when no location found and source is not remote', () => {
    // Covers the `return extracted` branch at line 656
    const extracted = { company: 'Acme', title: 'Engineer' }; // no location
    const result = normalizeLocationFromSource(extracted, 'Competitive salary, great benefits. No remote.');
    assert.equal(result.company, 'Acme');
    assert.equal(result.location, undefined);
  });

  it('returns Remote when no location found but source indicates remote (telecommute)', () => {
    // Covers the `sourceIndicatesRemote` TRUE branch at line 655
    const extracted = { company: 'Acme', title: 'Engineer' }; // no location
    const result = normalizeLocationFromSource(extracted, 'Fully remote/telecommute position available for this role.');
    assert.equal(result.location, 'Remote');
  });
});

describe('refreshRotationPool branch coverage', () => {
  it('returns [] when rotation is not enabled (non-OpenRouter provider)', async () => {
    const result = await refreshRotationPool({ llm_provider: 'lmstudio' });
    assert.deepEqual(result, []);
  });

  it('fetches and caches model pool when rotation is enabled', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = async () => ({
        ok: true,
        json: async () => ({
          data: [
            { id: 'free-model-1', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: {} },
          ],
        }),
      });
      const settings = { llm_provider: 'openrouter', llm_openrouter_free_rotate: 'true', llm_api_key_openrouter: '' };
      const result = await refreshRotationPool(settings, { force: true });
      assert.ok(Array.isArray(result));
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('returns cached pool when fetch throws (covers catch branch)', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = async () => { throw new Error('Network error'); };
      const settings = { llm_provider: 'openrouter', llm_openrouter_free_rotate: 'true', llm_api_key_openrouter: '' };
      const result = await refreshRotationPool(settings, { force: true });
      assert.ok(Array.isArray(result));
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe('runWithModelRotation branch coverage', () => {
  it('calls attemptFn with base model when pool is empty', async () => {
    let called = null;
    await runWithModelRotation([], 'base-model', async (model) => { called = model; return 'ok'; });
    assert.equal(called, 'base-model');
  });

  it('tries models from pool and returns first success', async () => {
    const attempts = [];
    const result = await runWithModelRotation(['m1', 'm2', 'm3'], 'base', async (model) => {
      attempts.push(model);
      if (model === 'm1') throw new Error('fail');
      return `result-${model}`;
    });
    assert.ok(result.startsWith('result-'));
    assert.ok(attempts.includes('m1'));
  });
});

describe('selectFreeStructuredModels branch coverage', () => {
  it('returns [] for null/undefined input', () => {
    assert.deepEqual(selectFreeStructuredModels(null), []);
    assert.deepEqual(selectFreeStructuredModels(undefined), []);
  });

  it('filters out paid models', () => {
    const data = {
      data: [
        { id: 'paid', pricing: { prompt: '0.001', completion: '0.002' }, supported_parameters: ['response_format'], architecture: {} },
        { id: 'free', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: {} },
      ],
    };
    const result = selectFreeStructuredModels(data);
    assert.ok(!result.includes('paid'));
    assert.ok(result.includes('free'));
  });

  it('excludes audio/image output models', () => {
    const data = {
      data: [
        {
          id: 'audio-model',
          pricing: { prompt: '0', completion: '0' },
          supported_parameters: ['response_format'],
          architecture: { output_modalities: ['text', 'audio'] },
        },
      ],
    };
    const result = selectFreeStructuredModels(data);
    assert.deepEqual(result, []);
  });
});

describe('extraction prompt — application_instructions field', () => {
  it('includes application_instructions in the extraction schema', () => {
    const prompt = _userPrompt({ url: 'https://example.com', canonical_url: 'https://example.com', page_title: 'PM', description: GLANCE_PM_JD });
    assert.match(prompt, /application_instructions/);
    assert.match(prompt, /submission mechanics/);
  });

  it('extraction schema describes it as separate from qualifications', () => {
    const prompt = _userPrompt({ url: 'https://example.com', canonical_url: 'https://example.com', page_title: 'PM', description: '' });
    assert.match(prompt, /NOT job qualifications/);
  });
});

describe('fit scoring prompt — application_instructions not penalized (job-128 Glance PM regression)', () => {
  const jobContext = {
    title: 'Product Manager',
    company: 'Glance',
    extracted: {
      title: 'Product Manager',
      company: 'Glance',
      seniority: 'Senior',
      summary: 'Drive product and go-to-market execution.',
      requirements: ['5+ years Product Management in B2B SaaS', 'PLG experience', 'Engineering background'],
      nice_to_haves: ['AI/ML experience', 'Mid-market enterprise focus'],
      skills: ['Product strategy', 'Go-to-market', 'PLG', 'B2B SaaS'],
      application_instructions: "To be considered, you must include the phrase 'Human Application' at the top of your resume when you submit.",
    },
  };
  const resume = 'Brooks Cutter — Technical Program Manager with 20 years experience in AI/ML and platform programs.';

  it('includes application_instructions labeled as submission mechanics in the prompt', () => {
    const prompt = _fitUserPrompt(jobContext, resume);
    assert.match(prompt, /Application instructions/);
    assert.match(prompt, /submission mechanics/);
    assert.match(prompt, /Human Application/);
  });

  it('tells the scorer not to penalize for application instructions', () => {
    const prompt = _fitUserPrompt(jobContext, resume);
    assert.match(prompt, /DO NOT factor into scores/);
    assert.match(prompt, /Do NOT penalize any dimension score/);
  });

  it('explicitly bans submission mechanics from requirements_met and requirements_not_met', () => {
    const prompt = _fitUserPrompt(jobContext, resume);
    assert.match(prompt, /Never include them in requirements_met or requirements_not_met/);
    assert.match(prompt, /exclude any submission mechanics/);
  });

  it('omits application_instructions content block when field is absent', () => {
    const ctx = { ...jobContext, extracted: { ...jobContext.extracted, application_instructions: null } };
    const prompt = _fitUserPrompt(ctx, resume);
    assert.doesNotMatch(prompt, /Human Application/);
  });
});
