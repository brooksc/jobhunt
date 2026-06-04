// Mirrors python/src/jobhunt/cleaning.py

export function cleanDescription({ selectedText = '', visibleText = '', structuredData = [] } = {}) {
  let source = (selectedText || '').trim();
  if (!source) {
    source = jobPostingText(structuredData, visibleText);
  }
  if (!source) {
    source = focusedVisibleJobText(visibleText).trim();
    const metadata = visibleJobMetadata(source);
    if (source && metadata.length > 0) {
      const unique = [...new Set(metadata)];
      source = [...unique, source].join('\n');
    }
  }
  return normalizeWhitespace(source);
}

function jobPostingText(structuredData, visibleText) {
  for (const item of structuredData) {
    const posting = findJobPosting(item);
    if (!posting) continue;
    const description = posting.description;
    if (typeof description !== 'string' || !description.trim()) continue;
    const metadata = jobPostingMetadata(posting);
    metadata.push(...visibleJobMetadata(visibleText));
    if (metadata.length > 0) {
      const unique = [...new Set(metadata)];
      return [...unique, description].join('\n');
    }
    return description;
  }
  return '';
}

function focusedVisibleJobText(visibleText) {
  const text = visibleText || '';
  const lines = text.split('\n');
  const detailIndex = lines.findIndex(line => /^\d+\s+of\s+\d+$/i.test(line.trim()));
  if (detailIndex === -1) return text;

  const detailLines = lines.slice(detailIndex + 1);
  const hasMicrosoftDetailMarkers = detailLines.some(line => /^job number$/i.test(line.trim())) &&
    detailLines.some(line => /^job description$/i.test(line.trim())) &&
    detailLines.some(line => /^work site$/i.test(line.trim()));
  if (!hasMicrosoftDetailMarkers) return text;

  return detailLines.join('\n');
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

function jobPostingMetadata(posting) {
  const metadata = [];
  append(metadata, 'Title', posting.title);
  append(metadata, 'Employment type', posting.employmentType);
  append(metadata, 'Job ID', identifierValue(posting.identifier));

  // schema.org remote work signal — TELECOMMUTE means fully remote
  if (posting.jobLocationType === 'TELECOMMUTE') {
    metadata.push('Work arrangement: Remote (telecommute)');
  }

  // Where applicants must be located (e.g. "United States", "USA")
  const locationReqs = applicantLocationRequirements(posting.applicantLocationRequirements);
  if (locationReqs.length > 0) {
    append(metadata, 'Hiring location', locationReqs.join('; '));
  }

  const locations = jobLocations(posting.jobLocation);
  if (locations.length > 0) {
    append(metadata, 'Location', locations.join('; '));
  }

  // Salary from baseSalary or estimatedSalary
  const salary = extractSalaryText(posting.baseSalary || posting.estimatedSalary);
  if (salary) append(metadata, 'Salary', salary);

  return metadata;
}

function applicantLocationRequirements(value) {
  if (!value) return [];
  const items = Array.isArray(value) ? value : [value];
  return items.flatMap(item => {
    if (typeof item === 'string') return [item];
    if (item && typeof item === 'object') {
      return [item.name || item.addressCountry || ''].filter(Boolean);
    }
    return [];
  });
}

function extractSalaryText(salary) {
  if (!salary || typeof salary !== 'object') return '';
  const val = salary.value;
  const currency = salary.currency || '';
  const unit = salary.unitText ? `/${salary.unitText.toLowerCase()}` : '';
  if (val && typeof val === 'object' && val.minValue && val.maxValue) {
    return `${currency}${val.minValue}–${val.maxValue}${unit}`;
  }
  if (val && typeof val === 'object' && val.minValue) {
    return `${currency}${val.minValue}+${unit}`;
  }
  if (typeof val === 'number') return `${currency}${val}${unit}`;
  return '';
}

function visibleJobMetadata(visibleText) {
  const lines = (visibleText || '').split('\n').map(l => l.trim()).filter(Boolean);
  const metadata = [];

  // Workday-style label → value patterns
  const locations = valuesAfterLabel(lines, 'locations', new Set(['time type', 'posted on', 'job requisition id']));
  if (locations.length && !locations.some(l => /^(professions|programs|life at microsoft|hiring tips)$/i.test(l))) {
    append(metadata, 'Location', locations.join('; '));
  }
  const timeType = valuesAfterLabel(lines, 'time type', new Set(['posted on', 'job requisition id', 'locations']));
  if (timeType.length) append(metadata, 'Employment type', timeType.join('; '));
  const requisition = valuesAfterLabel(lines, 'job requisition id', new Set(['locations', 'time type', 'posted on']));
  if (requisition.length) append(metadata, 'Job ID', requisition.join('; '));

  // Scan the first 60 lines for visual badge metadata (builtinseattle, LinkedIn, Greenhouse, etc.)
  // These appear as short standalone lines near the top of the page.
  const topLines = lines.slice(0, 60);

  const hasLocation = !metadata.some(m => /^Location:/i.test(m));
  if (hasLocation) {
    const locationLine = topLines.find(l =>
      /\bUnited States\b/i.test(l) &&
      /[,;]/.test(l) &&
      /\b(Washington|Redmond|Seattle|Bellevue|Kirkland|WA)\b/i.test(l)
    );
    if (locationLine) append(metadata, 'Location', locationLine);
  }

  const hasRemote = !metadata.some(m => /work arrangement/i.test(m));
  if (hasRemote) {
    const remoteSignal = topLines.find(l =>
      /^remote$/i.test(l) ||
      /hiring remotely/i.test(l) ||
      /fully remote/i.test(l) ||
      /work from home/i.test(l) ||
      /telecommute/i.test(l)
    );
    if (remoteSignal) {
      metadata.push('Work arrangement: Remote');
      if (!/^remote$/i.test(remoteSignal)) append(metadata, 'Hiring location', remoteSignal);
    } else if (topLines.some(l => /\bhybrid\b/i.test(l) && l.length < 30)) {
      metadata.push('Work arrangement: Hybrid');
    }
  }

  // Salary range — "160K-235K Annually", "$130,000-$260,000", "130K–260K", etc.
  // First try short standalone lines (badges); fall back to extracting the range
  // from a longer paragraph (e.g. Akamai's 800-char compensation paragraph).
  const hasSalary = !metadata.some(m => /salary/i.test(m));
  if (hasSalary) {
    const salaryLine = topLines.find(l =>
      l.length < 180 && (
        /\$[\d,]+\s*[-–]\s*\$?[\d,]+/i.test(l) ||
        /\d+[kK]\s*[-–]\s*\d+[kK]/i.test(l) ||
        (/annually|per year|\/yr/i.test(l) && /\d/.test(l))
      )
    );
    if (salaryLine) {
      append(metadata, 'Salary range', salaryLine);
    } else {
      // Scan for a salary range that appears in a dedicated Compensation/Salary section.
      // Only extract when a standalone section header precedes the paragraph — this avoids
      // pulling salary numbers from generic body text (e.g. funding amounts, role levels).
      const compIdx = lines.findIndex(l =>
        /^(?:compensation|salary|pay range|salary range|total compensation)$/i.test(l.trim())
      );
      if (compIdx >= 0) {
        const sectionText = lines.slice(compIdx, compIdx + 6).join(' ');
        const rangeMatch = sectionText.match(/\$[\d,]+\s*[-–]\s*\$?[\d,]+(?:\/(?:year|yr|hour|hr))?/i);
        if (rangeMatch) append(metadata, 'Salary range', rangeMatch[0]);
      } else {
        // Workday and similar platforms list salary without a $ sign at the bottom of the page:
        // "133,400 - 226,600 USD Annual". Scan the full page (not just topLines) for this pattern.
        // The currency code + "Annual" suffix is distinctive enough to avoid false positives.
        const workdayRe = /\b(\d{2,3}(?:,\d{3})+)\s*[-–—]\s*(\d{2,3}(?:,\d{3})+)\s+(?:USD|CAD|EUR|GBP)\s+Annual\b/i;
        const workdaySalaryLines = lines.filter(l => workdayRe.test(l) && l.length < 180);
        if (workdaySalaryLines.length) {
          append(metadata, 'Salary range', workdaySalaryLines.join('; '));
        }
      }
    }
  }

  // Seniority level — "Senior level", "Mid level", "Staff", etc.
  const seniorityLine = topLines.find(l =>
    /^(entry|junior|mid|senior|staff|principal|lead|director|vp|executive)\s+(level)?$/i.test(l.trim())
  );
  if (seniorityLine) append(metadata, 'Seniority', seniorityLine.trim());

  return metadata;
}

function valuesAfterLabel(lines, label, stopLabels) {
  const lowerLines = lines.map(l => l.toLowerCase());
  const start = lowerLines.indexOf(label);
  if (start === -1) return [];
  const values = [];
  for (const line of lines.slice(start + 1)) {
    const normalized = line.toLowerCase();
    if (stopLabels.has(normalized)) break;
    if (normalized.startsWith('posted ')) continue;
    values.push(line);
  }
  return values.slice(0, 4);
}

function identifierValue(identifier) {
  if (identifier && typeof identifier === 'object') {
    const value = identifier.value;
    return value != null ? String(value) : '';
  }
  if (typeof identifier === 'string') return identifier;
  return '';
}

function jobLocations(value) {
  if (Array.isArray(value)) {
    return value.flatMap(item => jobLocations(item));
  }
  if (!value || typeof value !== 'object') return [];
  const address = value.address;
  if (typeof address === 'string') return [address];
  if (!address || typeof address !== 'object') return [];
  const parts = [
    address.addressLocality,
    address.addressRegion,
    address.addressCountry,
  ].filter(Boolean);
  return parts.length ? [parts.join(', ')] : [];
}

function append(items, label, value) {
  if (value == null) return;
  const text = String(value).trim();
  if (text) items.push(`${label}: ${text}`);
}

function normalizeWhitespace(value) {
  // Preserve intentional line breaks between metadata lines and the body,
  // but collapse runs of spaces/tabs within a line.
  return value
    .split('\n')
    .map(line => line.replace(/[ \t]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
