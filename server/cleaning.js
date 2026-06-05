// Mirrors python/src/jobhunt/cleaning.py

export function cleanDescription({ selectedText = '', visibleText = '', structuredData = [] } = {}) {
  const selected = (selectedText || '').trim();
  if (selected) return normalizeWhitespace(selected);

  const parts = [];
  const vt = (visibleText || '').trim();
  if (vt) parts.push(vt);

  // Append HTML-stripped JSON-LD description as supplementary context.
  // Many job boards embed full salary bands, qualifications, etc. in the JSON-LD description
  // that are absent or truncated in the visible text (e.g. Workday wd1 pages, builtinseattle).
  const jsonLdDesc = extractJsonLdDescription(structuredData);
  if (jsonLdDesc) parts.push(jsonLdDesc);

  return normalizeWhitespace(parts.join('\n\n'));
}

function extractJsonLdDescription(structuredData) {
  for (const item of (structuredData || [])) {
    const posting = findJobPosting(item);
    if (!posting) continue;
    const parts = [];
    // Promote top-level JobPosting fields that don't appear in visible text
    if (posting.jobLocationType === 'TELECOMMUTE') parts.push('Work arrangement: Remote');
    const desc = posting.description;
    if (typeof desc === 'string' && desc.trim()) parts.push(stripHtml(desc));
    if (parts.length) return parts.join('\n');
  }
  return '';
}

function findJobPosting(value) {
  if (Array.isArray(value)) {
    for (const item of value) {
      const posting = findJobPosting(item);
      if (posting) return posting;
    }
    return null;
  }
  if (!value || typeof value !== 'object') return null;

  if (value['@graph']) {
    const posting = findJobPosting(value['@graph']);
    if (posting) return posting;
  }

  const typeValue = value['@type'];
  const types = Array.isArray(typeValue) ? typeValue : [typeValue];
  if (types.includes('JobPosting')) return value;

  return null;
}

function stripHtml(html) {
  const plain = html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(?:p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
  // Insert newlines between Workday-style salary bands in plain-text descriptions.
  // Workday bands end with "USD Annual" and the next band starts with a capital-letter label.
  // Only anchoring after "Annual" prevents accidentally splitting multi-word location names
  // like "San Francisco" (which also match a "Label: number" lookahead pattern).
  return plain.replace(
    /(?<=Annual)\s+(?=[A-Z][^:\n]{0,80}?:\s*\d{2,3}(?:,\d{3})+\s*[-–—])/g,
    '\n'
  );
}

function normalizeWhitespace(value) {
  return value
    .split('\n')
    .map(line => line.replace(/[ \t]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
