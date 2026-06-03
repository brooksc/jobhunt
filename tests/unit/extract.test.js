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
} from '../../server/extract.js';

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

    assert.equal(score, 82);
  });

  it('renormalizes when only known dimensions are present', () => {
    const score = computeOverallFitScore([
      { name: 'required_qualifications', score: 100 },
      { name: 'unknown', score: 0 },
      { name: 'skills', score: 80 },
    ]);

    assert.equal(score, 92);
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
