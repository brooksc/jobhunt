export function parseJdBlocks(text) {
  if (!text) return [];
  const lines = text.split('\n');

  // Skip leading boilerplate: nav links, metadata, short labels before the real JD prose.
  // "Real content" = a line that reads like a sentence (≥ 80 chars and contains punctuation
  // or common prose words), a recognisable section header keyword, or an emoji-led headline.
  const HEADER_RE = /^(overview|about|description|what you|role|position|responsibilities|qualifications|requirements|compensation|benefits|about us|the opportunity|the role|job summary|summary|who we|hiring)/i;
  const EMOJI_RE = /^\p{Emoji_Presentation}/u;
  const isProse = (l) => l.length >= 80 || (l.length >= 50 && /[,.]/.test(l));
  // For LinkedIn pages, "Feed post" marks the start of the actual post — skip profile chrome
  // before it by only counting lines that appear after it as candidate starts.
  const feedPostIdx = lines.findIndex(l => l.trim() === 'Feed post');
  const searchFrom = feedPostIdx >= 0 ? feedPostIdx + 1 : 0;

  let start = searchFrom;
  for (let i = searchFrom; i < Math.min(lines.length, searchFrom + 30); i++) {
    const l = lines[i].trim();
    if (isProse(l) || HEADER_RE.test(l) || EMOJI_RE.test(l)) { start = i; break; }
  }

  const blocks = [];
  let current = null;

  const flush = () => { if (current) { blocks.push(current); current = null; } };

  for (const raw of lines.slice(start)) {
    const line = raw.trim();

    if (!line) { flush(); continue; }

    // Stop at the LinkedIn concatenated duplicate — a very long run-on line that starts
    // with "Feed post" and contains the whole post without whitespace breaks.
    if (/^Feed post\S/.test(line)) { flush(); break; }

    // Bullet / list item
    const bulletContent = line.match(/^[•\-*◦·▪▸►▷→✅✓✔]\s+(.+)/)?.[1]
      ?? line.match(/^\d+[.)]\s+(.+)/)?.[1];
    if (bulletContent) {
      if (!current || current.type !== 'list') { flush(); current = { type: 'list', items: [] }; }
      current.items.push(bulletContent);
      continue;
    }

    // Section heading: ALL-CAPS short line, or line ending in ':', or known header words, or emoji-led
    const isHeading =
      (line.length < 80 && line === line.toUpperCase() && /[A-Z]{3}/.test(line) && !/[,;()\d]/.test(line))
      || (line.endsWith(':') && line.length < 70 && !line.includes('.'))
      || (line.length < 70 && HEADER_RE.test(line))
      || (EMOJI_RE.test(line) && line.length < 80);

    if (isHeading) {
      flush();
      blocks.push({ type: 'heading', text: line.replace(/:$/, '') });
      continue;
    }

    // Horizontal rule
    if (/^[-=]{3,}$/.test(line)) { flush(); blocks.push({ type: 'hr' }); continue; }

    // Paragraph text — merge consecutive lines into one paragraph
    if (!current || current.type !== 'paragraph') {
      flush();
      current = { type: 'paragraph', text: line };
    } else {
      current.text += ' ' + line;
    }
  }
  flush();

  // Drop trailing <hr> with nothing after it (LinkedIn separator before the duplicate)
  while (blocks.length && blocks[blocks.length - 1].type === 'hr') blocks.pop();

  return blocks;
}
