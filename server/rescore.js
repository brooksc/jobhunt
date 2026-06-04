#!/usr/bin/env node
// Recomputes fit scores for all jobs that have already been scored,
// using the current weights and missing-requirements penalty — no LLM calls needed.

import { computeOverallFitScore, FIT_DIMENSION_WEIGHTS } from './extract.js';
import { connect, defaultDbPath } from './db.js';

const DOMAIN_GAP_KEYWORDS = [
  'asic', 'fpga', 'rtl', 'tapeout', 'tape-out', 'silicon', 'emulation',
  'hyperscaler', 'cloud service', 'soc ', 'vlsi', 'gds',
];

function missingRequirementsPenalty(requirements_not_met) {
  if (!Array.isArray(requirements_not_met) || requirements_not_met.length === 0) return 0;
  let penalty = 0;
  for (const item of requirements_not_met) {
    const lower = item.toLowerCase();
    const isDomainGap = DOMAIN_GAP_KEYWORDS.some(kw => lower.includes(kw));
    penalty += isDomainGap ? 10 : 5;
  }
  return Math.min(penalty, 50);
}

const dbPath = process.env.JOBHUNT_DB_PATH || defaultDbPath();
console.log(`Database: ${dbPath}`);
const db = connect(dbPath);

const jobs = db.prepare(
  "SELECT id, fit_score, fit_score_json FROM jobs WHERE fit_status='succeeded' AND fit_score_json IS NOT NULL"
).all();

console.log(`Found ${jobs.length} scored jobs to reprocess`);

const update = db.prepare(
  "UPDATE jobs SET fit_score=?, fit_score_json=?, updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=?"
);

let updated = 0;
let skipped = 0;

for (const job of jobs) {
  let parsed;
  try {
    parsed = JSON.parse(job.fit_score_json);
  } catch {
    console.warn(`  job ${job.id}: invalid JSON, skipping`);
    skipped++;
    continue;
  }

  const { dimensions, requirements_not_met } = parsed;
  if (!Array.isArray(dimensions) || dimensions.length === 0) {
    skipped++;
    continue;
  }

  const baseScore = computeOverallFitScore(dimensions);
  if (baseScore === null) { skipped++; continue; }

  const penalty = missingRequirementsPenalty(requirements_not_met || []);
  const newScore = Math.max(0, baseScore - penalty);
  const oldScore = job.fit_score;

  const newJson = JSON.stringify({
    ...parsed,
    overall_score: newScore,
    requirements_penalty: penalty,
    score_weights: FIT_DIMENSION_WEIGHTS,
  });

  update.run(newScore, newJson, job.id);
  console.log(`  job ${job.id}: ${oldScore} → ${newScore} (penalty -${penalty})`);
  updated++;
}

console.log(`\nDone: ${updated} updated, ${skipped} skipped`);
