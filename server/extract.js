// Mirrors python/src/jobhunt/extract.py
// LLM extraction and fit scoring via OpenAI-compatible API.

import { jsonrepair } from 'jsonrepair';
import { expandMetros } from './metros.js';
import {
  connect, initDb, getSettings, setSetting,
  getLlmQueueForProcessing, getLlmRequestsByIds,
  getPendingExtractionForJob, getJobFitContext,
  markExtractionSucceeded, markExtractionFailed, resetJobExtraction,
  markFitSucceeded, markFitFailed,
  markLlmRequestRunning, queueFitScoresForAllResumes, getResume,
  getLlmRequestState, startLlmRequestAttempt, finishLlmRequestAttempt,
} from './db.js';

export const DEFAULT_LLM_BASE_URL = 'http://127.0.0.1:1234';
export const DEFAULT_LLM_MODEL = 'gemma-4-e4b-it-mlx';

export const ANTHROPIC_MODELS = [
  'claude-opus-4-8',
  'claude-sonnet-4-6',
  'claude-haiku-4-5-20251001',
];

export const GOOGLE_MODELS = [
  'gemini-2.5-pro',
  'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-1.5-pro',
  'gemini-1.5-flash',
];

export const OPENAI_DEFAULT_MODELS = [
  'gpt-4o',
  'gpt-4o-mini',
  'o3',
  'o3-mini',
];

export const OPENROUTER_DEFAULT_MODELS = [
  'openai/gpt-4o',
  'openai/gpt-4o-mini',
  'anthropic/claude-sonnet-4-6',
  'anthropic/claude-haiku-4-5',
  'google/gemini-2.5-flash-preview-05-20',
  'meta-llama/llama-3.3-70b-instruct',
  'mistralai/mistral-large',
];

// Returns the effective API base URL for a given provider.
export function resolveProviderBaseUrl(provider, baseUrl) {
  if (provider === 'openai') return 'https://api.openai.com';
  if (provider === 'openrouter') return 'https://openrouter.ai/api';
  return (baseUrl || process.env.JOBHUNT_LLM_BASE_URL || DEFAULT_LLM_BASE_URL).replace(/\/$/, '');
}

const TRUE_VALUES = new Set(['1', 'true', 'yes', 'on', 'enabled']);
const FALSE_VALUES = new Set(['0', 'false', 'no', 'off', 'disabled']);

export function parseBoolSetting(value, defaultVal = true) {
  if (value == null) return defaultVal;
  if (typeof value === 'boolean') return value;
  const text = String(value).trim().toLowerCase();
  if (TRUE_VALUES.has(text)) return true;
  if (FALSE_VALUES.has(text)) return false;
  return defaultVal;
}

// State abbreviation expansion for location matching
const STATE_ABBREV_TO_NAME = {
  al: 'alabama', ak: 'alaska', az: 'arizona', ar: 'arkansas', ca: 'california',
  co: 'colorado', ct: 'connecticut', de: 'delaware', dc: 'district of columbia',
  fl: 'florida', ga: 'georgia', hi: 'hawaii', id: 'idaho', il: 'illinois',
  in: 'indiana', ia: 'iowa', ks: 'kansas', ky: 'kentucky', la: 'louisiana',
  me: 'maine', md: 'maryland', ma: 'massachusetts', mi: 'michigan', mn: 'minnesota',
  ms: 'mississippi', mo: 'missouri', mt: 'montana', ne: 'nebraska', nv: 'nevada',
  nh: 'new hampshire', nj: 'new jersey', nm: 'new mexico', ny: 'new york',
  nc: 'north carolina', nd: 'north dakota', oh: 'ohio', ok: 'oklahoma', or: 'oregon',
  pa: 'pennsylvania', ri: 'rhode island', sc: 'south carolina', sd: 'south dakota',
  tn: 'tennessee', tx: 'texas', ut: 'utah', vt: 'vermont', va: 'virginia',
  wa: 'washington', wv: 'west virginia', wi: 'wisconsin', wy: 'wyoming',
};
const STATE_NAME_TO_ABBREV = Object.fromEntries(Object.entries(STATE_ABBREV_TO_NAME).map(([k, v]) => [v, k]));

export const FIT_DIMENSIONS = [
  'required_qualifications', 'preferred_qualifications', 'skills', 'experience_level', 'domain_fit',
];

export const FIT_DIMENSION_WEIGHTS = {
  required_qualifications: 0.45,
  preferred_qualifications: 0.05,
  skills: 0.15,
  experience_level: 0.20,
  domain_fit: 0.15,
};

// Keywords that indicate a domain-specific skill gap deserving a heavier score penalty
const DOMAIN_GAP_KEYWORDS = [
  'asic', 'fpga', 'rtl', 'tapeout', 'tape-out', 'silicon', 'emulation',
  'hyperscaler', 'cloud service', 'soc ', 'vlsi', 'gds',
];

// Returns how many points to subtract from the overall score based on missing requirements.
// Generic gaps cost 5 pts each; domain-specific gaps cost 10 pts each. Capped at 50.
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

export const MAX_DESCRIPTION_CHARS = 32000;
export const MAX_RESUME_CHARS = 12000;

// ------------------------------------------------------------------
// HTTP helpers — per-provider
// ------------------------------------------------------------------

async function postOpenAICompatibleCompletion({ baseUrl, apiKey, model, messages, timeout, schemaFormat }) {
  const base = { model, messages, temperature: 0, stream: false, max_tokens: 16384 };
  const formats = [schemaFormat, { type: 'json_object' }, null];
  const headers = /** @type {Record<string,string>} */ ({ 'Content-Type': 'application/json' });
  if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`;
  let lastBadResponse = null;
  for (const responseFormat of formats) {
    const payload = /** @type {any} */ ({ ...base });
    if (responseFormat != null) payload.response_format = responseFormat;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout * 1000);
    try {
      const res = await fetch(`${baseUrl}/v1/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      if (res.status === 400) {
        lastBadResponse = res;
        continue;
      }
      if (!res.ok) {
        const text = await res.text();
        throw new Error(`LLM HTTP ${res.status}: ${text.slice(0, 500)}`);
      }
      const data = /** @type {any} */ (await res.json());
      const content = data.choices[0].message.content;
      const modelName = data.model || null;
      const responseFormatType = responseFormat?.type || 'none';
      return { content, modelName, responseFormatType };
    } catch (e) {
      if (e.name === 'AbortError') throw new Error(`LLM request timed out after ${timeout}s`, { cause: e });
      throw e;
    } finally {
      clearTimeout(timer);
    }
  }
  if (lastBadResponse) {
    const text = await lastBadResponse.text();
    throw new Error(`LLM HTTP 400: ${text.slice(0, 500)}`);
  }
  throw new Error('chat completion produced no response');
}

async function postAnthropicCompletion({ apiKey, model, messages, timeout }) {
  const systemMsg = messages.find(m => m.role === 'system');
  const userMessages = messages.filter(m => m.role !== 'system');
  const payload = /** @type {any} */ ({
    model: model || 'claude-sonnet-4-6',
    max_tokens: 16384,
    messages: userMessages,
  });
  if (systemMsg) payload.system = systemMsg.content;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout * 1000);
  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey || '',
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Anthropic HTTP ${res.status}: ${text.slice(0, 500)}`);
    }
    const data = /** @type {any} */ (await res.json());
    const content = data.content?.[0]?.text ?? '';
    const modelName = data.model || null;
    return { content, modelName, responseFormatType: 'none' };
  } catch (e) {
    if (e.name === 'AbortError') throw new Error(`LLM request timed out after ${timeout}s`, { cause: e });
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

async function postGoogleCompletion({ apiKey, model, messages, timeout }) {
  const systemMsg = messages.find(m => m.role === 'system');
  const userMessages = messages.filter(m => m.role !== 'system');
  const contents = userMessages.map(m => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));
  const payload = /** @type {any} */ ({
    contents,
    generationConfig: { responseMimeType: 'application/json' },
  });
  if (systemMsg) payload.systemInstruction = { parts: [{ text: systemMsg.content }] };
  const resolvedModel = model || 'gemini-2.5-flash';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout * 1000);
  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${resolvedModel}:generateContent?key=${encodeURIComponent(apiKey || '')}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      }
    );
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Google HTTP ${res.status}: ${text.slice(0, 500)}`);
    }
    const data = /** @type {any} */ (await res.json());
    const content = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '';
    const modelName = data.modelVersion || resolvedModel;
    return { content, modelName, responseFormatType: 'none' };
  } catch (e) {
    if (e.name === 'AbortError') throw new Error(`LLM request timed out after ${timeout}s`, { cause: e });
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

async function postChatCompletion({ provider, baseUrl, apiKey, model, messages, timeout, schemaFormat }) {
  if (provider === 'anthropic') return postAnthropicCompletion({ apiKey, model, messages, timeout });
  if (provider === 'google') return postGoogleCompletion({ apiKey, model, messages, timeout });
  return postOpenAICompatibleCompletion({ baseUrl, apiKey, model, messages, timeout, schemaFormat });
}

// ------------------------------------------------------------------
// JSON parsing
// ------------------------------------------------------------------

function extractJsonObject(content) {
  const stripped = content.trim();
  const fenced = stripped.match(/```(?:json)?\s*(\{[\s\S]*?\})\s*```/);
  if (fenced) return fenced[1];
  const start = stripped.indexOf('{');
  const end = stripped.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) {
    throw new Error('LLM response did not contain a JSON object');
  }
  return stripped.slice(start, end + 1);
}

function loadsJsonLenient(text) {
  try {
    return JSON.parse(text);
  } catch {
    try {
      return JSON.parse(jsonrepair(text));
    } catch (e) {
      throw new Error(`LLM response could not be parsed as JSON: ${e.message}`, { cause: e });
    }
  }
}

function clampScore(value) {
  const n = Math.round(parseFloat(value));
  if (isNaN(n)) return 0;
  return Math.max(0, Math.min(100, n));
}

export function parseExtractedJob(content) {
  const data = loadsJsonLenient(extractJsonObject(content));
  return normalizeSalaryFromSource({
    company: data.company ?? null,
    title: data.title ?? null,
    location: data.location ?? null,
    remote_type: ['remote', 'hybrid', 'onsite', 'unknown'].includes(data.remote_type) ? data.remote_type : 'unknown',
    salary_min: data.salary_min ?? null,
    salary_max: data.salary_max ?? null,
    salary_hourly_min: data.salary_hourly_min ?? null,
    salary_hourly_max: data.salary_hourly_max ?? null,
    salary_currency: data.salary_currency ?? null,
    salary_note: data.salary_note ?? null,
    employment_type: ['full_time', 'part_time', 'contract', 'internship', 'unknown'].includes(data.employment_type) ? data.employment_type : 'unknown',
    seniority: data.seniority ?? null,
    skills: Array.isArray(data.skills) ? data.skills.filter(Boolean).map(String) : [],
    summary: data.summary ?? null,
    requirements: Array.isArray(data.requirements) ? data.requirements.filter(Boolean).map(String) : [],
    nice_to_haves: Array.isArray(data.nice_to_haves) ? data.nice_to_haves.filter(Boolean).map(String) : [],
    benefits: Array.isArray(data.benefits) ? data.benefits.filter(Boolean).map(String) : [],
    application_url: data.application_url ?? null,
    confidence: (data.confidence && typeof data.confidence === 'object') ? data.confidence : {},
  });
}

function parseSalaryAmount(raw) {
  const text = String(raw || '').trim().toLowerCase();
  const match = text.match(/(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/);
  if (!match) return null;
  const value = Number(match[1].replace(/,/g, ''));
  if (!Number.isFinite(value)) return null;
  return match[2] ? value * 1000 : value;
}

function moneyAmounts(text) {
  const amounts = [];
  const rangePatterns = [
    /(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*[-–—]\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/g,
    /[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(?:[$€£]\s*)?(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/g,
    /\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b/g,
  ];
  for (const re of rangePatterns) {
    for (const match of text.matchAll(re)) {
      if (match.length === 4) {
        const first = parseSalaryAmount(`${match[1]}${match[3] || ''}`);
        const second = parseSalaryAmount(`${match[2]}${match[3] || ''}`);
        if (first != null) amounts.push(first);
        if (second != null) amounts.push(second);
      } else {
        const first = parseSalaryAmount(`${match[1]}${match[2] || ''}`);
        const second = parseSalaryAmount(`${match[3]}${match[4] || match[2] || ''}`);
        if (first != null) amounts.push(first);
        if (second != null) amounts.push(second);
      }
    }
  }
  const patterns = [
    /[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/g,
    /(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/g,
    /\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b/g,
    /\b(\d+(?:\.\d+)?)\s*([kK])\b/g,
  ];
  for (const re of patterns) {
    for (const match of text.matchAll(re)) {
      const amount = parseSalaryAmount(`${match[1]}${match[2] || ''}`);
      if (amount != null) amounts.push(amount);
    }
  }
  return [...new Set(amounts)];
}

function hourlyAmounts(text) {
  if (!/\b(?:hr|hour|hourly)\b|\/\s*(?:hr|hour)/i.test(text)) return [];
  const amounts = moneyAmounts(text).filter(amount => amount > 0 && amount < 1000);
  const rangeBeforeHourly = /(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)\s*(?:USD|CAD|EUR|GBP)?\s*\/?\s*(?:hr|hour)\b/gi;
  for (const match of text.matchAll(rangeBeforeHourly)) {
    amounts.push(Number(match[1]), Number(match[2]));
  }
  return [...new Set(amounts)];
}

function minMax(values) {
  const nums = values.filter(v => Number.isFinite(v));
  if (!nums.length) return null;
  return { min: Math.min(...nums), max: Math.max(...nums) };
}

function currencyFromSalaryNote(note) {
  if (/\bUSD\s*\/\s*CAD\b|\bCAD\s*\/\s*USD\b/i.test(note)) return 'USD';
  if (/\bUSD\b|\$/i.test(note)) return 'USD';
  if (/\bEUR\b|€/i.test(note)) return 'EUR';
  if (/\bGBP\b|£/i.test(note)) return 'GBP';
  if (/\bCAD\b/i.test(note)) return 'CAD';
  return null;
}

function salaryTextForCurrency(note, currency) {
  if (!currency) return note;
  const otherCurrencies = {
    USD: /\b(?:CAD|EUR|GBP)\b|[€£]/i,
    CAD: /\b(?:USD|EUR|GBP)\b|[$€£]/i,
    EUR: /\b(?:USD|CAD|GBP)\b|[$£]/i,
    GBP: /\b(?:USD|CAD|EUR)\b|[$€]/i,
  };
  const ownCurrency = {
    USD: /\bUSD\b|\$/i,
    CAD: /\bCAD\b/i,
    EUR: /\bEUR\b|€/i,
    GBP: /\bGBP\b|£/i,
  };
  const own = ownCurrency[currency];
  const other = otherCurrencies[currency];
  if (!own || !other) return note;
  if (!other.test(note)) return note;
  const parts = note.split(/[;\n]+/).map(part => part.trim()).filter(Boolean);
  const filtered = parts.filter(part => own.test(part) && !other.test(part));
  return filtered.length ? filtered.join('\n') : note;
}

function normalizeSalaryCurrency(currency, note) {
  const value = String(currency || '').trim().toUpperCase();
  if (['USD', 'CAD', 'EUR', 'GBP'].includes(value)) return value;
  return currencyFromSalaryNote(note);
}

function salaryRangeValue(first, firstSuffix, second, secondSuffix) {
  const suffix = secondSuffix || firstSuffix || '';
  const low = parseSalaryAmount(`${first}${firstSuffix || suffix}`);
  const high = parseSalaryAmount(`${second}${secondSuffix || suffix}`);
  if (low == null || high == null || low < 1000 || high < 1000) return null;
  return { min: Math.min(low, high), max: Math.max(low, high) };
}

function lineRange(line) {
  const patterns = [
    /(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/i,
    /[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(?:[$€£]\s*)?(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?/i,
    /\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b/i,
  ];
  for (const pattern of patterns) {
    const match = line.match(pattern);
    if (!match) continue;
    if (pattern === patterns[0]) return salaryRangeValue(match[1], match[2], match[3], match[4]);
    return salaryRangeValue(match[1], match[2], match[3], match[4]);
  }
  return null;
}

function sentenceForIndex(text, index) {
  const startCandidates = [text.lastIndexOf('\n', index - 1), text.lastIndexOf('.', index - 1)];
  const start = Math.max(...startCandidates) + 1;
  const endCandidates = [text.indexOf('\n', index), text.indexOf('.', index)].filter(v => v !== -1);
  const end = endCandidates.length ? Math.min(...endCandidates) : text.length;
  return text.slice(start, end).trim();
}

function salaryBands(text) {
  const bands = [];
  const lines = String(text || '').split('\n').map(line => line.trim()).filter(Boolean);
  for (let i = 0; i < lines.length; i++) {
    const range = lineRange(lines[i]);
    if (!range) continue;
    const previous = i > 0 && !lineRange(lines[i - 1]) ? lines[i - 1] : '';
    bands.push({ ...range, label: `${previous} ${lines[i]}`.trim() });
  }

  const rangeRe = /(?:USD|CAD|EUR|GBP)?\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:per year|annually|annual|USD|CAD|EUR|GBP)?/gi;
  for (const match of text.matchAll(rangeRe)) {
    const range = salaryRangeValue(match[1], match[2], match[3], match[4]);
    if (!range) continue;
    const label = sentenceForIndex(text, match.index || 0);
    if (bands.some(b => b.min === range.min && b.max === range.max)) continue;
    bands.push({ ...range, label });
  }
  return bands;
}

function specificPreferredTerms(preferredLocations) {
  return parsePreferredLocations(preferredLocations)
    .filter(term => !/^(remote|united states|usa|us|u\.s\.|u\.s\.a\.)$/i.test(term.trim()));
}

function selectSalaryBand(bands, preferredLocations, note) {
  if (bands.length <= 1) return null;
  const terms = specificPreferredTerms(preferredLocations);
  for (const band of bands) {
    if (terms.some(term => termMatches(band.label, term))) return band;
  }
  const allOtherUSRe = /\bacross the U\.?S\.?\b|\ball (?:other )?U\.?S\.? locations\b|\bUnited States\b/i;
  // When user has location preferences but none matched a specific band,
  // use the "All Other US" band rather than the global min/max across all bands
  if (terms.length > 0) {
    const allOtherUS = bands.find(band => allOtherUSRe.test(band.label));
    if (allOtherUS) return allOtherUS;
  }
  if (/different range applicable to specific work locations/i.test(note)) {
    return bands.find(band => allOtherUSRe.test(band.label)) || null;
  }
  return null;
}

/**
 * @param {any} extracted
 * @param {{ preferredLocations?: string|null, sourceText?: string|null }} [opts]
 */
export function normalizeSalaryFromSource(extracted, { preferredLocations, sourceText } = {}) {
  const note = extracted.salary_note ? String(extracted.salary_note) : '';
  if (!note.trim()) {
    // salary_note is absent — try to recover salary bands from the raw source text.
    // This handles platforms (e.g. Workday) where the LLM may miss salary text that
    // has no $ sign ("133,400 - 226,600 USD Annual").
    if (!sourceText) return extracted;
    const src = String(sourceText);
    const salary_currency = normalizeSalaryCurrency(extracted.salary_currency, src);
    const filteredSrc = salaryTextForCurrency(src, salary_currency);
    const selectedBand = selectSalaryBand(salaryBands(filteredSrc), preferredLocations, filteredSrc);
    if (selectedBand) return { ...extracted, salary_currency, salary_min: selectedBand.min, salary_max: selectedBand.max };
    const annual = minMax(moneyAmounts(filteredSrc).filter(a => a >= 1000));
    if (!annual) return { ...extracted, salary_currency };
    return { ...extracted, salary_currency, salary_min: annual.min, salary_max: annual.max };
  }
  const salary_currency = normalizeSalaryCurrency(extracted.salary_currency, note);
  const salaryText = salaryTextForCurrency(note, salary_currency);

  const hourly = minMax(hourlyAmounts(salaryText));
  if (hourly) {
    return {
      ...extracted,
      salary_currency,
      salary_hourly_min: hourly.min,
      salary_hourly_max: hourly.max,
      salary_min: Math.round(hourly.min * 2080),
      salary_max: Math.round(hourly.max * 2080),
    };
  }

  const sourceSalaryText = sourceText ? salaryTextForCurrency(String(sourceText), salary_currency) : '';
  const sourceSelectedBand = sourceSalaryText && specificPreferredTerms(preferredLocations).length
    ? selectSalaryBand(salaryBands(sourceSalaryText), preferredLocations, sourceSalaryText)
    : null;
  if (sourceSelectedBand) {
    return { ...extracted, salary_currency, salary_min: sourceSelectedBand.min, salary_max: sourceSelectedBand.max };
  }

  const selectedBand = selectSalaryBand(salaryBands(salaryText), preferredLocations, salaryText);
  if (selectedBand) {
    return { ...extracted, salary_currency, salary_min: selectedBand.min, salary_max: selectedBand.max };
  }

  const annual = minMax(moneyAmounts(salaryText).filter(amount => amount >= 1000));
  if (!annual) return { ...extracted, salary_currency };
  return { ...extracted, salary_currency, salary_min: annual.min, salary_max: annual.max };
}

function sourceIndicatesRemote(description) {
  const text = description || '';
  return (
    /^Remote(?:\s*[-–—]\s*(?:United States|USA|U\.S\.|US))?\b/im.test(text) ||
    /^Work arrangement:\s*Remote\b/im.test(text) ||
    /\bWork site\s*0\s+days?\s*\/\s*week\s+in-office\b/i.test(text) ||
    /\bRemote\s+or\s+Hybrid\b/i.test(text) ||
    /\bopen to remote candidates\b/i.test(text) ||
    /\bHiring Remotely\b/i.test(text) ||
    /\bFully Remote\b/i.test(text) ||
    /\bWork from Home\b/i.test(text) ||
    /\bTelecommute\b/i.test(text) ||
    /"jobLocationType"\s*:\s*"TELECOMMUTE"/i.test(text)
  );
}

// Check the captured URL for job-board-specific remote filter parameters.
// These are reliable signals: the job was surfaced by an explicit "remote only" filter.
function urlIndicatesRemote(url) {
  if (!url) return false;
  try {
    const u = new URL(url);
    const p = u.searchParams;
    const host = u.hostname;
    if (host.includes('levels.fyi') && p.get('perkIds')?.split(',').includes('58')) return true; // perkId 58 = Fully Remote
    if (host.includes('indeed.com') && (p.get('remotejob') === '1' || p.get('l') === 'Remote')) return true;
    if (host.includes('linkedin.com') && p.get('f_WT') === '2') return true;
    if (host.includes('glassdoor.com') && p.get('remoteWorkType') === '1') return true;
  } catch { /* invalid URL */ }
  return false;
}

export function normalizeRemoteTypeFromSource(extracted, description, url) {
  if (extracted.remote_type === 'remote') return extracted;
  if (sourceIndicatesRemote(description) || urlIndicatesRemote(url)) return { ...extracted, remote_type: 'remote' };
  if (/\bWork site\s*[1-5]\s+days?\s*\/\s*week\s+in-office\b/i.test(description || '')) {
    return { ...extracted, remote_type: 'hybrid' };
  }
  return extracted;
}

function sourceLocationFromTitle(description, title) {
  if (!title) return null;
  const lines = (description || '').split('\n').map(l => l.trim()).filter(Boolean);
  const normalizedTitle = title.trim().toLowerCase();
  const metadataLocation = metadataValue(lines, 'Location');
  if (metadataLocation) return metadataLocation;
  const basedInLocation = locationFromBasedIn(description);
  if (basedInLocation) return basedInLocation;
  for (let i = 0; i < lines.length - 1; i++) {
    if (lines[i].toLowerCase() !== normalizedTitle) continue;
    const candidate = lines[i + 1];
    if (/\bUnited States\b/i.test(candidate) && /[,;]/.test(candidate)) return candidate.replace(/\s+\+\s*/g, ' + ');
    if (/^[A-Z][A-Za-z .'-]+,\s*[A-Z]{2}\b/.test(candidate)) return candidate;
  }
  return null;
}

function locationFromBasedIn(description) {
  const match = (description || '').match(/\b(?:hybrid|remote|onsite|on-site)\s+role\s+based\s+in\s+([^.\n(]+?)(?:\s*\(|\.|\n|$)/i);
  return match?.[1]?.trim().replace(/\s*,\s*$/, '') || null;
}

function remoteLocationFromSource(description) {
  const text = description || '';
  const match = text.match(/^Remote(?:\s*[-–—]\s*((?:United States|USA|U\.S\.|US)(?:\s+or\s+[A-Za-z]+)?))?\b/im);
  if (!match) return null;
  return match[1] ? `Remote - ${match[1].trim()}` : 'Remote';
}

export function normalizeLocationFromSource(extracted, description) {
  const remoteLocation = remoteLocationFromSource(description);
  const loc = String(extracted.location || '').trim();
  const isBareCountry = /^(USA|United States|U\.S\.A?\.?|US)$/i.test(loc);
  if (remoteLocation && (!extracted.location || /^remote$/i.test(loc) || isBareCountry)) {
    return { ...extracted, location: remoteLocation };
  }
  if (extracted.location) return extracted;
  const location = sourceLocationFromTitle(description, extracted.title);
  if (!location) {
    if (sourceIndicatesRemote(description)) return { ...extracted, location: 'Remote' };
    return extracted;
  }
  return { ...extracted, location };
}

export function normalizeEmploymentFromSource(extracted, description) {
  if (extracted.employment_type !== 'full_time') return extracted;
  const text = description || '';
  if (/\b(full[-\s]?time|regular employee|permanent)\b/i.test(text) || /"employmentType"\s*:\s*"FULL_TIME"/i.test(text)) {
    return extracted;
  }
  return { ...extracted, employment_type: 'unknown' };
}

function metadataValue(lines, label) {
  const prefix = `${label.toLowerCase()}:`;
  for (const line of lines) {
    if (!line.toLowerCase().startsWith(prefix)) continue;
    const value = line.slice(prefix.length).trim();
    if (value) return value;
  }
  return null;
}

function structuredHiringOrganizationName(description) {
  const text = description || '';
  const match = text.match(/"hiringOrganization"\s*:\s*\{[\s\S]{0,1000}?"name"\s*:\s*"([^"]+)"/i);
  return match?.[1] || null;
}

export function normalizeCompanyFromSource(extracted, description) {
  if (extracted.company) return extracted;
  const company = structuredHiringOrganizationName(description);
  if (!company) return extracted;
  return { ...extracted, company };
}

function parseFitScore(content) {
  const data = loadsJsonLenient(extractJsonObject(content));
  const dimensions = Array.isArray(data.dimensions)
    ? data.dimensions.map(d => ({
        name: String(d.name || ''),
        score: clampScore(d.score),
        rationale: d.rationale ? String(d.rationale) : '',
      }))
    : [];
  const requirements_met = Array.isArray(data.requirements_met) ? data.requirements_met.filter(Boolean).map(String) : [];
  const requirements_not_met = Array.isArray(data.requirements_not_met) ? data.requirements_not_met.filter(Boolean).map(String) : [];
  const baseScore = computeOverallFitScore(dimensions);
  const penalty = missingRequirementsPenalty(requirements_not_met);
  const overall_score = baseScore !== null ? Math.max(0, baseScore - penalty) : null;
  return {
    overall_score,
    requirements_penalty: penalty,
    summary: data.summary ?? null,
    requirements_met,
    requirements_not_met,
    score_weights: FIT_DIMENSION_WEIGHTS,
    dimensions,
  };
}

export function computeOverallFitScore(dimensions) {
  if (!Array.isArray(dimensions) || dimensions.length === 0) return null;
  let weightedScore = 0;
  let totalWeight = 0;
  for (const dimension of dimensions) {
    const weight = FIT_DIMENSION_WEIGHTS[dimension?.name];
    if (!weight) continue;
    weightedScore += clampScore(dimension.score) * weight;
    totalWeight += weight;
  }
  return totalWeight > 0 ? Math.round(weightedScore / totalWeight) : null;
}

// ------------------------------------------------------------------
// Location filtering
// ------------------------------------------------------------------

function parsePreferredLocations(preferredLocations) {
  if (!preferredLocations) return [];
  const terms = [];
  const seen = new Set();
  for (const raw of preferredLocations.split(',')) {
    const token = raw.trim();
    if (!token) continue;
    const base = token.toLowerCase();
    if (seen.has(base)) continue;
    terms.push(token);
    seen.add(base);
    if (STATE_ABBREV_TO_NAME[base]) {
      const full = STATE_ABBREV_TO_NAME[base];
      if (!seen.has(full)) { terms.push(full[0].toUpperCase() + full.slice(1)); seen.add(full); }
    }
    if (STATE_NAME_TO_ABBREV[base]) {
      const abbr = STATE_NAME_TO_ABBREV[base];
      if (!seen.has(abbr)) { terms.push(abbr.toUpperCase()); seen.add(abbr); }
    }
  }
  return terms;
}

function normalizeForMatch(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function termMatches(location, term) {
  const haystack = normalizeForMatch(location);
  const needle = normalizeForMatch(term);
  if (!needle) return false;
  if (needle.length === 2) return new RegExp(`\\b${needle.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(haystack);
  return haystack.includes(needle);
}

function matchLocationTerms(location, terms) {
  if (!location) return { hasMatch: false, matched: [] };
  const matched = terms.filter(t => termMatches(location, t));
  return { hasMatch: matched.length > 0, matched };
}

/**
 * @param {any} extracted
 * @param {{ preferredLocations?: string|null, allowRemote?: boolean, allowHybrid?: boolean, allowOnsite?: boolean, filterEnabled?: boolean }} [opts]
 */
export function applyLocationFilter(extracted, { preferredLocations, allowRemote = true, allowHybrid = true, allowOnsite = true, filterEnabled = true } = {}) {
  if (!filterEnabled) return { ...extracted, meets_criteria: true };
  const terms = parsePreferredLocations(preferredLocations);
  const remoteType = extracted.remote_type;
  const { hasMatch } = matchLocationTerms(extracted.location, terms);

  if (!terms.length) {
    if (remoteType === 'remote') return { ...extracted, meets_criteria: Boolean(allowRemote) };
    if (remoteType === 'hybrid') return { ...extracted, meets_criteria: Boolean(allowHybrid) };
    if (remoteType === 'onsite') return { ...extracted, meets_criteria: Boolean(allowOnsite) };
    return { ...extracted, meets_criteria: Boolean(allowOnsite) };
  }

  if (remoteType === 'remote') return { ...extracted, meets_criteria: Boolean(allowRemote) };
  if (remoteType === 'hybrid') {
    return { ...extracted, meets_criteria: Boolean(allowHybrid && hasMatch) };
  }
  if (remoteType === 'onsite') {
    return { ...extracted, meets_criteria: Boolean(allowOnsite && hasMatch) };
  }

  return { ...extracted, meets_criteria: Boolean(allowOnsite && hasMatch) };
}

// ------------------------------------------------------------------
// Prompts
// ------------------------------------------------------------------

function systemPrompt() {
  return 'You extract structured job posting data. Return only one valid JSON object. Do not include markdown, commentary, or guessed values. If a field is not present in the source, use null for scalar fields and [] for list fields.';
}

function locationPreferencePrompt(preferredLocations, { allowRemote, allowHybrid, allowOnsite }) {
  const terms = (preferredLocations || '').split(',').map(t => t.trim()).filter(Boolean);
  if (!terms.length && allowRemote && allowHybrid && allowOnsite) {
    return '\nLocation preference context:\n- No location preferences configured. Extract all location/remote values present in the source.\n';
  }
  const termsText = terms.length ? terms.join(', ') : 'No location preference terms.';
  const allowed = [allowRemote ? 'remote' : null, allowHybrid ? 'hybrid' : null, allowOnsite ? 'onsite' : null].filter(Boolean).join(', ');
  return `\nLocation preference context:\n- Preferred locations: ${termsText}\n- Allowed remote modes: ${allowed}\n- Keep state abbreviations and city names as they appear in source text (e.g. "WA", "Seattle", "Redmond"), and prefer exact string matches.\n- If the posting has one of the preferred locations, keep that location text and mark remote_type accordingly.\n`;
}

/**
 * @param {any} pending
 * @param {{ preferredLocations?: string|null, allowRemote?: boolean, allowHybrid?: boolean, allowOnsite?: boolean }} [opts]
 */
function userPrompt(pending, { preferredLocations, allowRemote, allowHybrid, allowOnsite } = {}) {
  const locationRules = `
Location and remote_type rules:
- Set location to the raw location(s) listed in the posting (city, state, region, or "Multiple Locations").
- Infer remote_type from the work arrangement, NOT the location field:
  - "remote" → posting says remote, WFH, work from home, 0 days in office, fully remote, telecommute.
  - "hybrid" → posting specifies a mix (e.g. "2 days/week in office", "hybrid").
  - "onsite" → posting requires in-person / in-office with no remote option.
  - "unknown" → no work arrangement information found.
- Examples: "Work site 0 days/week in-office – remote" → remote_type="remote". "Work site 3 days/week in-office" → remote_type="hybrid".`;
  const locationPrefRules = locationPreferencePrompt(preferredLocations, { allowRemote, allowHybrid, allowOnsite });
  return `Extract job information from the posting below.

Return JSON with exactly these keys:
- company: string or null
- title: string or null
- location: string or null
- remote_type: one of "remote", "hybrid", "onsite", "unknown"
- salary_min: integer or null
- salary_max: integer or null
- salary_hourly_min: number or null
- salary_hourly_max: number or null
- salary_currency: string or null
- salary_note: string or null
- employment_type: one of "full_time", "part_time", "contract", "internship", "temporary", "unknown"
- seniority: string or null
- skills: array of strings
- summary: string or null
- requirements: array of strings
- nice_to_haves: array of strings
- benefits: array of strings
- application_url: string or null
- confidence: object mapping field names to confidence numbers from 0 to 1

Salary rules:
- ALWAYS extract salary_min and salary_max when any numeric pay range appears in the posting.
- If hourly pay appears, extract the raw hourly rate range into salary_hourly_min and salary_hourly_max.
- Store values as annual integers (e.g. 119800, not "119,800" or "$119,800").
- Some job boards (e.g. Workday) express annual salary without a $ sign: "133,400 - 226,600 USD Annual". Treat these as annual USD amounts.
- If the posting lists an hourly rate, convert to annual using exactly 2,080 hours/year:
  hourly × 40 hours/week × 52 weeks/year = hourly × 2080.
  Do not subtract holidays, PTO, unpaid time, or use any other annual-hours estimate.
  Examples: $75/hr → salary_min=156000; $75–$95/hr → salary_min=156000, salary_max=197600.
  Example: $85/hr–$105/hr → salary_min=176800, salary_max=218400.
- When the posting lists multiple annual salary bands, include all salary bands in salary_note.
  The application verifies salary_min/salary_max from salary_note and uses the lowest and highest salary values found there.
- When multiple bands exist for seniority or job family (not location), use the absolute lowest/highest.
- Always put the original salary text in salary_note, including any location-specific bands omitted from salary_min/max.
- If salary bands differ by location, preserve each location label with its range in salary_note, such as "WA: $205,000-$216,500 USD".
- If salary bands differ by currency, preserve each currency label and range in salary_note; do not combine currencies into one range.

List extraction rules:
- Extract every distinct concrete skill, technology, tool, or domain named anywhere in the posting (responsibilities, requirements, role scope, and team/charter description), even when there is no "Skills" heading. Aim for completeness (typically 6-15); do not stop at a handful. Do not invent skills that are not in the posting.
- Extract hard requirements into requirements. If the posting lists qualifications without separating "required" from "preferred" (e.g. a single "What we're looking for", "Qualifications", or "Minimum qualifications" list), treat every bullet in that list as a requirement and capture them all.
- Extract preferred qualifications and useful background signals into nice_to_haves. When the posting has no explicit "Preferred" or "Nice to have" section, mine the responsibilities, role summary, and required qualifications for domain signals: technologies, industry verticals, cross-functional partner teams (e.g. "engineering, design, research"), and products or platforms mentioned as context. Even a single mention is enough — nice_to_haves must not be empty when the posting names any relevant domain, partner, product, or technology.
- Use concise noun phrases copied or closely paraphrased from the posting.
${locationRules}
${locationPrefRules}
Known metadata:
URL: ${pending.canonical_url || pending.url}
Page title: ${pending.page_title}

Job description:
${(pending.description || '').slice(0, MAX_DESCRIPTION_CHARS)}`.trim();
}

function fitSystemPrompt() {
  return 'You are a recruiting analyst. Compare a candidate\'s resume against a job posting and judge how well the candidate fits the role. Return only one valid JSON object. Do not include markdown, commentary, or guessed values. Be objective: base scores only on evidence in the resume and the job description.';
}

const FIT_DIMENSION_GUIDE = {
  required_qualifications: 'how well the resume satisfies the job\'s hard requirements / must-haves',
  preferred_qualifications: 'how well the resume satisfies the nice-to-have / preferred qualifications',
  skills: 'overlap between the candidate\'s skills and the skills the job lists',
  experience_level: 'alignment between the candidate\'s seniority/years and the role\'s level',
  domain_fit: 'relevance of the candidate\'s industry/domain background to this role',
};

function fitUserPrompt(context, resume) {
  const extracted = context.extracted || {};
  const block = (label, value) => {
    if (Array.isArray(value)) {
      const items = value.filter(Boolean).map(String);
      return `${label}:\n${items.length ? items.map(v => `- ${v}`).join('\n') : '- (none listed)'}`;
    }
    return `${label}: ${value || '(not specified)'}`;
  };
  const jobSection = [
    block('Title', extracted.title || context.title),
    block('Company', extracted.company || context.company),
    block('Seniority', extracted.seniority),
    block('Summary', extracted.summary),
    block('Required qualifications', extracted.requirements),
    block('Preferred / nice-to-have', extracted.nice_to_haves),
    block('Skills', extracted.skills),
  ].join('\n');
  const dimensionLines = FIT_DIMENSIONS.map(name => `  - "${name}": ${FIT_DIMENSION_GUIDE[name]}`).join('\n');
  const dimensionNames = FIT_DIMENSIONS.map(name => `"${name}"`).join(', ');
  return `Score how well the candidate fits this job.

Return JSON with exactly these keys:
- summary: string — 1-3 sentences explaining the overall fit
- requirements_met: array of concise strings naming job requirements the resume clearly satisfies; include evidence when useful
- requirements_not_met: array of concise strings naming important job requirements with weak, missing, or unclear evidence in the resume
- dimensions: array of exactly ${FIT_DIMENSIONS.length} objects, one per dimension, each with:
  - name: one of ${dimensionNames}
  - score: integer 0-100
  - rationale: string — one sentence justifying the score

Dimensions to evaluate (use these exact names):
${dimensionLines}

Scoring guidance:
- 0 = no evidence of fit; 50 = partial / mixed fit; 100 = clearly exceeds what the role needs.
- If the job omits information for a dimension, score conservatively and say so in the rationale.
- Do not provide an overall score. The application computes it from the dimension scores.
- For requirements_met and requirements_not_met, focus on concrete job requirements, not generic praise.
- If evidence is mixed or absent, put the item in requirements_not_met and explain what is missing.

Job posting:
${jobSection}

Candidate resume:
${resume.slice(0, MAX_RESUME_CHARS)}`.trim();
}

// Fixed prompt "scaffolding" sizes (chars) for extraction and fit, measured by
// building each prompt with empty variable content. Used by the cost estimator
// to account for per-request prompt overhead beyond the JD / resume text.
export function promptOverheadChars(locationOpts = {}) {
  const extractChars = systemPrompt().length +
    userPrompt({ url: '', canonical_url: '', page_title: '', description: '' }, locationOpts).length;
  const fitChars = fitSystemPrompt().length +
    fitUserPrompt({ title: '', company: '', extracted: {} }, '').length;
  return { extractChars, fitChars };
}

// ------------------------------------------------------------------
// LMStudioExtractor
// ------------------------------------------------------------------

export class LMStudioExtractor {
  /** @param {{ provider?: string, baseUrl?: string, apiKey?: string, model?: string, timeout?: number, modelPool?: string[], preferredLocations?: string|null, allowRemote?: boolean, allowHybrid?: boolean, allowOnsite?: boolean, filterEnabled?: boolean }} [opts] */
  constructor({ provider, baseUrl, apiKey, model, timeout = 120, modelPool, preferredLocations, allowRemote = true, allowHybrid = true, allowOnsite = true, filterEnabled = true } = {}) {
    this.provider = provider || 'lmstudio';
    this.baseUrl = resolveProviderBaseUrl(this.provider, baseUrl);
    this.apiKey = apiKey || '';
    this.model = model || process.env.JOBHUNT_LLM_MODEL || DEFAULT_LLM_MODEL;
    this.modelPool = modelPool || [];
    this.timeout = timeout;
    this.preferredLocations = preferredLocations;
    this.allowRemote = allowRemote;
    this.allowHybrid = allowHybrid;
    this.allowOnsite = allowOnsite;
    this.filterEnabled = filterEnabled;
  }

  async extract(pending) {
    const messages = [
      { role: 'system', content: systemPrompt() },
      { role: 'user', content: userPrompt(pending, { preferredLocations: this.preferredLocations, allowRemote: this.allowRemote, allowHybrid: this.allowHybrid, allowOnsite: this.allowOnsite }) },
    ];
    const schemaFormat = { type: 'json_schema', json_schema: { name: 'extracted_job', strict: true, schema: extractedJobSchema() } };
    // Parse inside the rotation attempt so a model returning bad JSON fails over.
    const { extracted: raw, modelName, responseFormatType } = await runWithModelRotation(this.modelPool, this.model, async (model) => {
      const { content, modelName, responseFormatType } = await postChatCompletion({
        provider: this.provider, baseUrl: this.baseUrl, apiKey: this.apiKey, model, timeout: this.timeout, messages, schemaFormat,
      });
      try {
        return { extracted: parseExtractedJob(content), modelName, responseFormatType };
      } catch (err) {
        err.llmContent = content;
        err.modelName = modelName;
        err.responseFormatType = responseFormatType;
        throw err;
      }
    });
    let extracted = normalizeSalaryFromSource(raw, {
      preferredLocations: this.preferredLocations,
      sourceText: pending.source_text || pending.description,
    });
    extracted = normalizeCompanyFromSource(extracted, pending.source_text || pending.description);
    extracted = normalizeLocationFromSource(extracted, pending.source_text || pending.description);
    extracted = normalizeRemoteTypeFromSource(extracted, pending.source_text || pending.description, pending.canonical_url || pending.url);
    extracted = normalizeEmploymentFromSource(extracted, pending.source_text || pending.description);
    extracted = applyLocationFilter(extracted, { preferredLocations: this.preferredLocations, allowRemote: this.allowRemote, allowHybrid: this.allowHybrid, allowOnsite: this.allowOnsite, filterEnabled: this.filterEnabled });
    return { extracted, modelName, responseFormatType };
  }
}

function extractedJobSchema() {
  return {
    type: 'object',
    properties: {
      company: { type: ['string', 'null'] },
      title: { type: ['string', 'null'] },
      location: { type: ['string', 'null'] },
      remote_type: { type: 'string', enum: ['remote', 'hybrid', 'onsite', 'unknown'] },
      salary_min: { type: ['integer', 'null'] },
      salary_max: { type: ['integer', 'null'] },
      salary_hourly_min: { type: ['number', 'null'] },
      salary_hourly_max: { type: ['number', 'null'] },
      salary_currency: { type: ['string', 'null'] },
      salary_note: { type: ['string', 'null'] },
      employment_type: { type: 'string', enum: ['full_time', 'part_time', 'contract', 'internship', 'temporary', 'unknown'] },
      seniority: { type: ['string', 'null'] },
      skills: { type: 'array', items: { type: 'string' } },
      summary: { type: ['string', 'null'] },
      requirements: { type: 'array', items: { type: 'string' } },
      nice_to_haves: { type: 'array', items: { type: 'string' } },
      benefits: { type: 'array', items: { type: 'string' } },
      application_url: { type: ['string', 'null'] },
      confidence: { type: 'object' },
    },
    required: ['company', 'title', 'location', 'remote_type', 'salary_min', 'salary_max', 'salary_hourly_min', 'salary_hourly_max', 'salary_currency', 'salary_note', 'employment_type', 'seniority', 'skills', 'summary', 'requirements', 'nice_to_haves', 'benefits', 'application_url', 'confidence'],
    additionalProperties: false,
  };
}

// ------------------------------------------------------------------
// FitScorer
// ------------------------------------------------------------------

export class FitScorer {
  /** @param {{ provider?: string, baseUrl?: string, apiKey?: string, model?: string, timeout?: number, modelPool?: string[] }} [opts] */
  constructor({ provider, baseUrl, apiKey, model, timeout = 120, modelPool } = {}) {
    this.provider = provider || 'lmstudio';
    this.baseUrl = resolveProviderBaseUrl(this.provider, baseUrl);
    this.apiKey = apiKey || '';
    this.model = model || process.env.JOBHUNT_LLM_MODEL || DEFAULT_LLM_MODEL;
    this.modelPool = modelPool || [];
    this.timeout = timeout;
  }

  async score(context, resume) {
    const messages = [
      { role: 'system', content: fitSystemPrompt() },
      { role: 'user', content: fitUserPrompt(context, resume) },
    ];
    const schemaFormat = { type: 'json_schema', json_schema: { name: 'fit_score', strict: true, schema: fitScoreSchema() } };
    return runWithModelRotation(this.modelPool, this.model, async (model) => {
      const { content, modelName, responseFormatType } = await postChatCompletion({
        provider: this.provider, baseUrl: this.baseUrl, apiKey: this.apiKey, model, timeout: this.timeout, messages, schemaFormat,
      });
      try {
        return { fit: parseFitScore(content), modelName, responseFormatType };
      } catch (err) {
        err.llmContent = content;
        err.modelName = modelName;
        err.responseFormatType = responseFormatType;
        throw err;
      }
    });
  }
}

function fitScoreSchema() {
  return {
    type: 'object',
    properties: {
      summary: { type: 'string' },
      requirements_met: { type: 'array', items: { type: 'string' } },
      requirements_not_met: { type: 'array', items: { type: 'string' } },
      dimensions: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            score: { type: 'integer', minimum: 0, maximum: 100 },
            rationale: { type: 'string' },
          },
          required: ['name', 'score', 'rationale'],
          additionalProperties: false,
        },
        minItems: FIT_DIMENSIONS.length,
        maxItems: FIT_DIMENSIONS.length,
      },
    },
    required: ['summary', 'requirements_met', 'requirements_not_met', 'dimensions'],
    additionalProperties: false,
  };
}

// ------------------------------------------------------------------
// Extraction runner (in-process, async)
// ------------------------------------------------------------------

// Simple in-process lock — Electron runs as a single process
let _extractionRunning = false;

// Cloud providers handle many requests at once; local servers (LM Studio, or a
// custom OpenAI-compatible endpoint that's usually a single local instance)
// process one at a time. Concurrency is the number of LLM calls run in parallel.
const HOSTED_PROVIDERS = new Set(['openai', 'anthropic', 'google', 'openrouter']);
const HOSTED_CONCURRENCY = 5;
export function providerConcurrency(provider) {
  return HOSTED_PROVIDERS.has(provider) ? HOSTED_CONCURRENCY : 1;
}

// ------------------------------------------------------------------
// OpenRouter free-model rotation
// ------------------------------------------------------------------
// When enabled, spread requests round-robin across OpenRouter's free models
// that advertise structured-output support, with failover so one flaky model
// doesn't fail the request. The pool is fetched from OpenRouter and cached.

const ROTATION_TTL_MS = 60 * 60 * 1000;
const ROTATE_FAILOVER_TRIES = 4;
let _rotationCache = { ids: [], fetchedAt: 0 };
let _rotateCounter = 0;

function rotationEnabled(settings) {
  return (settings.llm_provider || 'lmstudio') === 'openrouter'
    && String(settings.llm_openrouter_free_rotate) === 'true';
}

// Filters an OpenRouter /models payload to free models that support structured
// output (JSON schema / response_format). Exported for testing.
export function selectFreeStructuredModels(data) {
  return (data?.data || []).filter(m => {
    const free = Number(m.pricing?.prompt) === 0 && Number(m.pricing?.completion) === 0;
    const sp = m.supported_parameters || [];
    const structured = sp.includes('structured_outputs') || sp.includes('response_format');
    // Text-only output — excludes free image/audio models (e.g. Lyria, whose
    // output is ['text','audio']) that also advertise structured output but
    // aren't usable as chat extractors. Multimodal input is fine; we send text.
    const arch = m.architecture || {};
    const outputs = arch.output_modalities || (typeof arch.modality === 'string' ? arch.modality.split('->')[1]?.split('+') : null);
    const textOut = !outputs || (outputs.includes('text') && outputs.every(x => x === 'text'));
    return free && structured && textOut;
  }).map(m => m.id);
}

// Refreshes (when stale) and returns the free-model rotation pool, or [] when
// rotation is off / provider isn't OpenRouter. Network failures keep the last
// good pool. Call before building extractors/scorers for a run.
export async function refreshRotationPool(settings, { force = false } = {}) {
  if (!rotationEnabled(settings)) return [];
  const now = Date.now();
  if (!force && _rotationCache.ids.length && now - _rotationCache.fetchedAt < ROTATION_TTL_MS) return _rotationCache.ids;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 6000);
    let data;
    try {
      const r = await fetch('https://openrouter.ai/api/v1/models', { signal: controller.signal });
      if (!r.ok) throw new Error(`OpenRouter HTTP ${r.status}`);
      data = await r.json();
    } finally {
      clearTimeout(timer);
    }
    const ids = selectFreeStructuredModels(data);
    if (ids.length) _rotationCache = { ids, fetchedAt: now };
    return _rotationCache.ids;
  } catch {
    return _rotationCache.ids;
  }
}

// The current (cached) rotation pool for these settings, read synchronously
// when building an extractor/scorer.
export function rotationPoolFor(settings) {
  return rotationEnabled(settings) ? _rotationCache.ids : [];
}

// Runs attemptFn(model) against a model pool with round-robin start and
// failover (up to ROTATE_FAILOVER_TRIES models). Falls back to the single
// configured model when the pool is empty. Exported for testing.
export async function runWithModelRotation(modelPool, model, attemptFn) {
  if (!modelPool || !modelPool.length) return attemptFn(model);
  const tries = Math.min(ROTATE_FAILOVER_TRIES, modelPool.length);
  let lastErr;
  for (let i = 0; i < tries; i++) {
    const m = modelPool[(_rotateCounter++) % modelPool.length];
    try {
      return await attemptFn(m);
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr;
}

export async function runExtraction({ dbPath, extractor, limit = 10, scorer }) {
  if (_extractionRunning) return { processed: 0, succeeded: 0, failed: 0 };
  _extractionRunning = true;
  try {
    return await _runExtractionInner({ dbPath, extractor, limit, scorer });
  } finally {
    _extractionRunning = false;
  }
}

export async function runExtractionForSelected({ dbPath, extractor, requestIds, scorer }) {
  if (_extractionRunning) return { processed: 0, succeeded: 0, failed: 0 };
  _extractionRunning = true;
  try {
    const items = getLlmRequestsByIds(requestIds, dbPath).filter(item => item.status === 'queued' || item.status === 'failed');
    const concurrency = providerConcurrency((extractor || scorer)?.provider);
    let processed = 0, succeeded = 0, failed = 0;
    for (let i = 0; i < items.length; i += concurrency) {
      const batch = items.slice(i, i + concurrency);
      const results = await Promise.all(batch.map(item => processSingleQueueRequest({ dbPath, extractor, item, scorer })));
      for (const { wasProcessed, didSucceed } of results) {
        if (wasProcessed) {
          processed++;
          if (didSucceed) succeeded++; else failed++;
        }
      }
    }
    return { processed, succeeded, failed };
  } finally {
    _extractionRunning = false;
  }
}

async function _runExtractionInner({ dbPath, extractor, limit = 10, scorer }) {
  if (isQueuePaused(dbPath)) return { processed: 0, succeeded: 0, failed: 0 };

  const concurrency = providerConcurrency((extractor || scorer)?.provider);
  // When rotating across free models, individual models are expected to fail
  // (rate limits / overload) — failover handles it, so don't pause the queue.
  const rotating = !!((extractor || scorer)?.modelPool?.length);
  let failureStreak = 0, processed = 0, succeeded = 0, failed = 0;
  const handledIds = new Set();
  let paused = false;

  while (processed < limit && !paused) {
    if (isQueuePaused(dbPath)) break;
    const want = Math.min(concurrency, limit - processed);
    const batch = getLlmQueueForProcessing(dbPath, want).filter(item => !handledIds.has(item.id));
    if (!batch.length) break;
    batch.forEach(item => handledIds.add(item.id));

    // Fire the batch concurrently (1 for local, HOSTED_CONCURRENCY for cloud).
    const results = await Promise.all(
      batch.map(item => processSingleQueueRequest({ dbPath, extractor, item, scorer }))
    );

    for (const { wasProcessed, didSucceed } of results) {
      if (!wasProcessed) continue;
      processed++;
      if (didSucceed) {
        succeeded++;
        failureStreak = 0;
      } else {
        failed++;
        failureStreak++;
        // Two failures in a row → the endpoint is likely misconfigured; stop.
        if (!rotating && failureStreak >= 2) { pauseLlmQueueForErrors(dbPath); paused = true; }
      }
    }
  }
  return { processed, succeeded, failed };
}

async function processSingleQueueRequest({ dbPath, extractor, item, scorer }) {
  if (item.request_type === 'fit_score') {
    return processFitScoreRequest({ dbPath, scorer, item });
  }

  const pending = getPendingExtractionForJob(dbPath, item.job_id);
  if (!pending) return { wasProcessed: false, didSucceed: false };
  if (!markLlmRequestRunning(item.id, dbPath)) return { wasProcessed: false, didSucceed: false };
  const running = getLlmRequestState(item.id, dbPath);
  const attemptId = startLlmRequestAttempt(dbPath, item.id, {
    baseUrl: extractor?.baseUrl,
    modelRequested: extractor?.model,
    promptChars: pending.description ? String(pending.description).length : null,
  });

  try {
    const { extracted, modelName, responseFormatType } = await extractor.extract(pending);
    const confidenceValues = Object.values(extracted.confidence || {});
    const confidence = confidenceValues.length ? confidenceValues.reduce((a, b) => a + b, 0) / confidenceValues.length : null;
    markExtractionSucceeded(pending.job_id, extracted, dbPath, item.id, modelName, confidence);
    finishLlmRequestAttempt(dbPath, attemptId, { status: 'succeeded', modelReturned: modelName, responseFormat: responseFormatType });
    queueFitScoresForAllResumes(dbPath, pending.job_id);
    return { wasProcessed: true, didSucceed: true };
  } catch (err) {
    markExtractionFailed(pending.job_id, String(err), dbPath, item.id);
    finishLlmRequestAttempt(dbPath, attemptId, {
      status: 'failed',
      modelReturned: err.modelName || running?.model || null,
      responseFormat: err.responseFormatType || null,
      error: String(err),
      responsePreview: err.llmContent,
      responseChars: err.llmContent ? String(err.llmContent).length : null,
    });
    return { wasProcessed: true, didSucceed: false };
  }
}

async function processFitScoreRequest({ dbPath, scorer, item }) {
  const resumeId = item.resume_id;
  if (!resumeId) {
    // Legacy fit request with no resume — nothing to score against; cancel it.
    initDb(dbPath).prepare("UPDATE llm_requests SET status='canceled', finished_at=? WHERE id=?").run(new Date().toISOString(), item.id);
    return { wasProcessed: false, didSucceed: false };
  }
  const resume = getResume(dbPath, resumeId);
  if (!resume || !String(resume.text || '').trim()) {
    markFitFailed(item.job_id, resumeId, resume ? 'Resume has no text to score against.' : 'Resume no longer exists.', dbPath, item.id);
    return { wasProcessed: true, didSucceed: false };
  }
  if (!scorer) {
    markFitFailed(item.job_id, resumeId, 'No LLM scorer configured.', dbPath, item.id);
    return { wasProcessed: true, didSucceed: false };
  }

  const context = getJobFitContext(dbPath, item.job_id);
  if (!context) {
    // Extraction hasn't completed yet. Re-queue extraction and reset fit_score
    // to queued so it retries after extraction finishes. Returning wasProcessed:false
    // means this iteration doesn't count toward the failure streak so the queue
    // won't pause on this transient dependency.
    const db = initDb(dbPath);
    const job = db.prepare("SELECT extraction_status FROM jobs WHERE id=?").get(item.job_id);
    if (job && job.extraction_status !== 'succeeded') {
      resetJobExtraction(item.job_id, dbPath);
    }
    db.prepare("UPDATE llm_requests SET status='queued', error=NULL, started_at=NULL, finished_at=NULL WHERE id=?").run(item.id);
    return { wasProcessed: false, didSucceed: false };
  }

  if (!markLlmRequestRunning(item.id, dbPath)) return { wasProcessed: false, didSucceed: false };
  const running = getLlmRequestState(item.id, dbPath);
  const attemptId = startLlmRequestAttempt(dbPath, item.id, {
    baseUrl: scorer?.baseUrl,
    modelRequested: scorer?.model,
    promptChars: JSON.stringify(context.extracted || {}).length + String(resume.text || '').length,
  });

  try {
    const { fit, modelName, responseFormatType } = await scorer.score(context, resume.text);
    markFitSucceeded(item.job_id, resumeId, fit, dbPath, item.id, modelName);
    finishLlmRequestAttempt(dbPath, attemptId, { status: 'succeeded', modelReturned: modelName, responseFormat: responseFormatType });
    process.emit('jobhunt:job-ready', {
      jobNumber: item.job_number,
      title: item.title,
      resumeName: resume.name,
      fitScore: typeof fit?.overall_score === 'number' ? fit.overall_score : null,
    });
    return { wasProcessed: true, didSucceed: true };
  } catch (err) {
    markFitFailed(item.job_id, resumeId, String(err), dbPath, item.id);
    finishLlmRequestAttempt(dbPath, attemptId, {
      status: 'failed',
      modelReturned: err.modelName || running?.model || null,
      responseFormat: err.responseFormatType || null,
      error: String(err),
      responsePreview: err.llmContent,
      responseChars: err.llmContent ? String(err.llmContent).length : null,
    });
    return { wasProcessed: true, didSucceed: false };
  }
}

function isQueuePaused(dbPath) {
  const db = connect(dbPath);
  const settings = getSettings(db);
  return parseBoolSetting(settings.llm_queue_paused, false);
}

function pauseLlmQueueForErrors(dbPath) {
  const db = connect(dbPath);
  setSetting(db, 'llm_queue_paused', 'true');
  // Signal any listener (e.g. Electron main process) that an auto-pause occurred.
  process.emit('jobhunt:queue-auto-paused');
}

export function makeExtractorFromSettings(settings) {
  const metroTerms = expandMetros(settings.preferred_metros || '');
  const manualTerms = (settings.preferred_locations || '').split(',').map(t => t.trim()).filter(Boolean);
  const combinedLocations = [...new Set([...metroTerms, ...manualTerms])].join(', ');
  const filterEnabled = parseBoolSetting(settings.location_filter_enabled, true);
  return new LMStudioExtractor({
    provider: settings.llm_provider || 'lmstudio',
    baseUrl: settings.llm_base_url,
    apiKey: settings.llm_api_key || '',
    model: settings.llm_model,
    modelPool: rotationPoolFor(settings),
    timeout: parseFloat(settings.llm_timeout || '60'),
    preferredLocations: filterEnabled ? (combinedLocations || null) : null,
    allowRemote: parseBoolSetting(settings.location_allow_remote, true),
    allowHybrid: parseBoolSetting(settings.location_allow_hybrid, true),
    allowOnsite: parseBoolSetting(settings.location_allow_onsite, true),
    filterEnabled,
  });
}

export function makeScorerFromSettings(settings) {
  return new FitScorer({
    provider: settings.llm_provider || 'lmstudio',
    baseUrl: settings.llm_base_url,
    apiKey: settings.llm_api_key || '',
    model: settings.llm_model,
    modelPool: rotationPoolFor(settings),
    timeout: parseFloat(settings.llm_timeout || '60'),
  });
}
