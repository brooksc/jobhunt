(function () {
  const SHOW_MORE_RE = /\b(show more|see more|read more|view more|expand)\b/i;
  const NOISE_ANCESTOR_SELECTORS = "nav, header, footer, aside, form, dialog, details";
  const NOISE_CLASS_HINTS = /\b(cookie|consent|banner|menu|navbar|nav|header|footer|toolbar|announcement|promo|cookiebar|sign\s*in|sign\s*up|subscribe|newsletter)\b/i;

  function isLikelyLayoutElement(node) {
    const current = node.closest ? node.closest(NOISE_ANCESTOR_SELECTORS) : null;
    if (current) {
      return true;
    }
    const text = `${node.id || ""} ${node.className || ""}`;
    return NOISE_CLASS_HINTS.test(text);
  }

  function asText(node) {
    return (node.textContent || node.getAttribute("aria-label") || "").trim();
  }

  function shouldClickExpansionControl(node) {
    const text = asText(node).toLowerCase();
    if (!SHOW_MORE_RE.test(text)) {
      return false;
    }

    // Skip anchors with a real href — those navigate the page, not expand content.
    // Real expansion controls use href="#", href="", or no href at all.
    const tag = (node.tagName || '').toUpperCase();
    if (tag === 'A') {
      const href = (node.getAttribute ? node.getAttribute('href') : node.href) || '';
      if (href && !href.startsWith('#')) return false;
    }

    if (isLikelyLayoutElement(node)) {
      return false;
    }

    return true;
  }

  function collectStructuredData(doc) {
    const fromDoc = Array.from(doc.querySelectorAll('script[type="application/ld+json"]'))
      .map((script) => script.textContent || "")
      .map((text) => text.trim())
      .filter(Boolean)
      .flatMap((text) => {
        try {
          return [JSON.parse(text)];
        } catch (_error) {
          return [];
        }
      });

    // Also collect JSON-LD from same-origin iframes (e.g. iCIMS custom career pages).
    const fromIframes = [];
    for (const iframe of doc.querySelectorAll('iframe')) {
      try {
        const iDoc = iframe.contentDocument;
        if (!iDoc) continue;
        const items = Array.from(iDoc.querySelectorAll('script[type="application/ld+json"]'))
          .map((s) => (s.textContent || "").trim())
          .filter(Boolean)
          .flatMap((t) => { try { return [JSON.parse(t)]; } catch (_) { return []; } });
        fromIframes.push(...items);
      } catch (_) {}
    }

    return [...fromDoc, ...fromIframes];
  }

  function collectIframeText(doc) {
    // Extract visible text from same-origin iframes. Some job boards (e.g. iCIMS custom
    // career portals) render the actual job content inside an iframe while the outer page
    // only contains navigation/branding, causing body.innerText to miss all job details.
    const parts = [];
    for (const iframe of doc.querySelectorAll('iframe')) {
      try {
        const iDoc = iframe.contentDocument;
        if (!iDoc || !iDoc.body) continue;
        const text = (iDoc.body.innerText || "").trim();
        if (text.length > 300) parts.push(text);
      } catch (_) {}
    }
    return parts.join('\n\n');
  }

  function collectVisibleText(doc, win) {
    // Always capture the raw top of the page first.
    // Job boards put key metadata (Remote, salary, seniority, location) in a structured
    // header card that Readability treats as sidebar and strips. The first ~2000 chars of
    // body.innerText almost always covers that card before the nav noise dominates.
    const rawTop = (doc.body && doc.body.innerText ? doc.body.innerText : "").slice(0, 2000).trim();

    let combined = "";
    if (typeof Readability !== "undefined") {
      try {
        const clone = doc.cloneNode(true);
        const article = new Readability(clone, { charThreshold: 100 }).parse();
        if (article && article.textContent && article.textContent.trim().length > 200) {
          const body = article.textContent.trim();
          // Prepend raw header so metadata badges are never lost, then append the
          // Readability-cleaned body for the full description text.
          combined = rawTop ? `${rawTop}\n\n---\n\n${body}` : body;
        }
      } catch (_error) {
        // fall through
      }
    }
    if (!combined) {
      // Fallback: raw visible text
      combined = (doc.body && doc.body.innerText ? doc.body.innerText : "").trim();
    }

    // Supplement with Next.js data when present. Some CSR pages (e.g. Cribl) put
    // the full JD in __NEXT_DATA__ / __next_f rather than rendering it into the DOM.
    const nextjsText = win ? collectNextJSText(win) : "";
    if (nextjsText) {
      // Always include Next.js data; prepend DOM text only if it adds signal
      return combined.length > 200
        ? `${combined}\n\n---\n\n${nextjsText}`
        : nextjsText;
    }

    // Supplement with same-origin iframe content. Some job boards (e.g. iCIMS custom
    // career portals) embed the entire job description in a same-origin iframe while
    // the outer page contains only navigation/branding.
    const iframeText = collectIframeText(doc);
    if (iframeText) {
      return combined.length > 300
        ? `${combined}\n\n---\n\n${iframeText}`
        : iframeText;
    }

    return combined;
  }

  function collectSelectedText(win) {
    const selection = win.getSelection ? win.getSelection() : null;
    return selection ? selection.toString().trim() : "";
  }

  function collectNextJSText(win) {
    // Extract text from Next.js RSC data (__next_f) and __NEXT_DATA__ page props.
    // CSR Next.js pages (e.g. Cribl) embed the full job description in these
    // payloads rather than rendering it into the DOM.
    const JOB_SIGNALS = /\$[\d,]+|\b(?:salary|compensation|pay range|requirements|qualifications|responsibilities|experience|description)\b/i;
    const parts = [];

    // ── __NEXT_DATA__ (page props JSON, available on all Next.js pages) ──────
    if (win.__NEXT_DATA__ && typeof win.__NEXT_DATA__ === 'object') {
      try {
        const raw = JSON.stringify(win.__NEXT_DATA__);
        if (JOB_SIGNALS.test(raw)) {
          // Walk the JSON extracting long string values (likely description fields)
          function extractStrings(obj, depth) {
            if (depth > 8 || !obj) return [];
            if (typeof obj === 'string') return obj.length > 80 ? [obj] : [];
            if (Array.isArray(obj)) return obj.flatMap(v => extractStrings(v, depth + 1));
            if (typeof obj === 'object') return Object.values(obj).flatMap(v => extractStrings(v, depth + 1));
            return [];
          }
          const strings = extractStrings(win.__NEXT_DATA__, 0)
            .filter(s => JOB_SIGNALS.test(s))
            .map(s => s.replace(/<[^>]{0,200}>/g, ' ').replace(/\s+/g, ' ').trim())
            .filter(s => s.length > 100);
          if (strings.length) parts.push([...new Set(strings)].join('\n'));
        }
      } catch (_) { /* ignore */ }
    }

    // ── __next_f RSC payload ─────────────────────────────────────────────────
    const arr = win.__next_f;
    if (Array.isArray(arr)) {
      const texts = arr
        .filter(c => Array.isArray(c) && c[0] === 1 && typeof c[1] === 'string')
        .filter(c => c[1].length >= 200 && c[1].length <= 30000)
        // Accept entity-encoded HTML OR plain text with job signals
        .filter(c => (/&lt;[a-z]/.test(c[1]) || JOB_SIGNALS.test(c[1])) && JOB_SIGNALS.test(c[1]))
        .map(c => c[1]
          .replace(/&lt;\/?[a-z][^&]{0,50}&gt;/gi, ' ')
          .replace(/&amp;/g, '&')
          .replace(/&nbsp;/g, ' ')
          .replace(/&lt;/g, '<')
          .replace(/&gt;/g, '>')
          .replace(/&quot;/g, '"')
          .replace(/<[^>]{0,200}>/g, ' ')
          .replace(/\s+/g, ' ')
          .trim()
        )
        .filter(s => s.length > 100);
      if (texts.length) parts.push([...new Set(texts)].join('\n'));
    }

    return parts.join('\n\n---\n\n');
  }

  function collectCanonicalUrl(doc) {
    const canonical = doc.querySelector('link[rel="canonical"]');
    const href = canonical && canonical.href ? canonical.href.trim() : "";
    return href || null;
  }

  function extractStructuredDescriptions(structuredData) {
    const descriptions = [];
    function walk(obj) {
      if (!obj || typeof obj !== 'object') return;
      if (Array.isArray(obj)) { obj.forEach(walk); return; }
      const typeValue = obj['@type'];
      const types = Array.isArray(typeValue) ? typeValue : [typeValue];
      if (types.includes('JobPosting')) {
        if (typeof obj.description === 'string') descriptions.push(obj.description);
        return;
      }
      if (obj['@graph']) walk(obj['@graph']);
    }
    walk(structuredData);
    return descriptions.join('\n');
  }

  function capturePreflight(payload) {
    const visibleText = payload.visible_text || "";
    const selectedText = payload.selected_text || "";
    const structuredData = Array.isArray(payload.structured_data) ? payload.structured_data : [];
    const structuredText = extractStructuredDescriptions(structuredData);
    const text = `${payload.page_title || ""}\n${visibleText}\n${selectedText}\n${structuredText}`;

    const titleVal = (payload.page_title || "").trim() || null;

    const locMatch = text.match(
      /\b(Remote(?:\s*[-–]\s*(?:United States|USA|US|Canada))?|Hybrid|Onsite|On-site|Hiring Remotely|[A-Z][a-zA-Z\s]{1,20},\s*(?:[A-Z]{2}|[A-Z][a-z]{3,}))\b/
    );
    const locationVal = locMatch ? locMatch[1].trim() : null;

    const salaryMatch = text.match(
      /\$[\d,]+(?:\.?\d+)?[kK]?(?:\/(?:yr|year))?\s*(?:[-–—]|to)\s*\$[\d,]+(?:\.?\d+)?[kK]?(?:\/(?:yr|year))?(?:\s*(?:USD|annually))?|\$[\d,]+[kK]|\b\d{2,3}[kK]\s*[-–—]\s*\d{2,3}[kK]\b|\b\d{2,3},\d{3}\s*[-–—]\s*\d{2,3},\d{3}\s*USD/i
    );
    const salaryVal = salaryMatch ? salaryMatch[0].trim() : null;

    let remoteVal = null;
    if (/\b(fully\s+remote|work\s+from\s+home|WFH|telecommute|hiring\s+remotely|0\s+days?\s*\/\s*week)\b/i.test(text)) remoteVal = "Remote";
    else if (/\bhybrid\b/i.test(text)) remoteVal = "Hybrid";
    else if (/\b(onsite|on-site|in-office)\b/i.test(text)) remoteVal = "Onsite";
    else if (/\bremote\b/i.test(text)) remoteVal = "Remote";

    return {
      titleVal,
      locationVal,
      salaryVal,
      remoteVal,
      structuredData: structuredData.length,
      selectedText: Boolean(selectedText.trim()),
      visibleChars: visibleText.length,
      url: payload.url || "",
    };
  }

  function showCapturePreflight(preflight) {
    return new Promise((resolve) => {
      const existing = document.getElementById("jobhunt-capture-preflight");
      if (existing) existing.remove();

      const root = document.createElement("div");
      root.id = "jobhunt-capture-preflight";
      root.style.cssText = [
        "position:fixed", "right:16px", "top:16px", "z-index:2147483647",
        "width:320px", "background:#111827", "color:#f9fafb",
        "border:1px solid rgba(255,255,255,.18)", "border-radius:8px",
        "box-shadow:0 18px 48px rgba(0,0,0,.35)", "font:13px -apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
        "padding:12px"
      ].join(";");

      // Build the static skeleton; no page-derived values in innerHTML.
      root.innerHTML = `
        <div style="font-weight:700;font-size:14px;margin-bottom:8px;">Jobhunt capture preflight</div>
        <div data-jh-rows></div>
        <div data-jh-stats style="margin-top:8px;color:#9ca3af;font-size:12px;line-height:1.35;"></div>
        <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:12px;">
          <span data-jh-countdown style="font-size:13px;color:#86efac;font-weight:600;line-height:1.4;">Saving in 5…</span>
          <div style="display:flex;gap:8px;">
            <button data-jh-cancel style="background:transparent;color:#d1d5db;border:1px solid #4b5563;border-radius:6px;padding:6px 10px;cursor:pointer;">Cancel</button>
            <button data-jh-open style="background:transparent;color:#93c5fd;border:1px solid #3b82f6;border-radius:6px;padding:6px 10px;cursor:pointer;">Open in app</button>
          </div>
        </div>
      `;

      // Populate check rows using textContent so page-derived values cannot inject markup.
      const checks = [
        ["Title", preflight.titleVal],
        ["Location", preflight.locationVal],
        ["Salary", preflight.salaryVal],
        ["Remote/work mode", preflight.remoteVal],
      ];
      function truncate(s, n) { return s.length > n ? s.slice(0, n - 1) + "…" : s; }
      const rowsContainer = root.querySelector("[data-jh-rows]");
      checks.forEach(([label, val]) => {
        const row = document.createElement("div");
        row.style.cssText = "display:flex;align-items:baseline;justify-content:space-between;gap:12px;padding:3px 0;";
        const labelEl = document.createElement("span");
        labelEl.style.cssText = "white-space:nowrap;color:#cbd5e1;font-size:12px;line-height:1.4;";
        labelEl.textContent = label;
        const valEl = document.createElement("span");
        valEl.style.cssText = `color:${val ? "#4ade80" : "#f87171"};font-size:12px;line-height:1.4;text-align:right;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:180px;`;
        valEl.textContent = val ? truncate(val, 38) : "missing";
        row.appendChild(labelEl);
        row.appendChild(valEl);
        rowsContainer.appendChild(row);
      });

      // Populate stats line — visibleChars and structuredData are numbers, safe to interpolate.
      const statsEl = root.querySelector("[data-jh-stats]");
      const statsText = `${preflight.visibleChars.toLocaleString()} visible chars · ${preflight.structuredData} structured item${preflight.structuredData === 1 ? "" : "s"}${preflight.selectedText ? " · selected text" : ""} · `;
      statsEl.appendChild(document.createTextNode(statsText));
      const issueTitle = encodeURIComponent(`Capture issue: ${preflight.titleVal || preflight.url}`);
      const issueBody = encodeURIComponent([
        `**Job URL:** ${preflight.url}`,
        ``,
        `**Preflight results:**`,
        `- Title: ${preflight.titleVal || "(missing)"}`,
        `- Location: ${preflight.locationVal || "(missing)"}`,
        `- Salary: ${preflight.salaryVal || "(missing)"}`,
        `- Remote: ${preflight.remoteVal || "(missing)"}`,
        ``,
        `**Capture stats:** ${preflight.visibleChars.toLocaleString()} visible chars · ${preflight.structuredData} structured item${preflight.structuredData === 1 ? "" : "s"}`,
        ``,
        `**What was wrong:**`,
        `<!-- Describe what was missing or incorrect -->`,
      ].join("\n"));
      const issueUrl = `https://github.com/brooksc/jobhunt/issues/new?title=${issueTitle}&body=${issueBody}`;
      // Issue URL includes: job URL, preflight title/location/salary/remote, and capture stats.
      // It does NOT include: full job description text, resume content, or LLM responses.
      const issueLink = document.createElement("a");
      issueLink.href = issueUrl;
      issueLink.target = "_blank";
      issueLink.rel = "noopener";
      issueLink.title = "Opens GitHub Issues with job URL and preflight fields (title, location, salary, remote) pre-filled for your report";
      issueLink.style.cssText = "color:#6b7280;text-decoration:underline;cursor:pointer;";
      issueLink.textContent = "Report capture issue";
      statsEl.appendChild(issueLink);
      document.body.appendChild(root);

      let secondsLeft = 5;
      const countdownEl = root.querySelector("[data-jh-countdown]");
      const timer = setInterval(() => {
        secondsLeft -= 1;
        if (secondsLeft <= 0) {
          clearInterval(timer);
          root.remove();
          resolve("save");
        } else {
          countdownEl.textContent = `Saving in ${secondsLeft}…`;
        }
      }, 1000);

      root.querySelector("[data-jh-cancel]").addEventListener("click", () => { clearInterval(timer); root.remove(); resolve(null); });
      root.querySelector("[data-jh-open]").addEventListener("click", () => {
        clearInterval(timer);
        // Show feedback while the service worker saves then opens — keeps dialog visible
        // so the user knows something is happening before the app focuses.
        countdownEl.textContent = "Saving…";
        root.querySelector("[data-jh-cancel]").style.display = "none";
        root.querySelector("[data-jh-open]").disabled = true;
        setTimeout(() => { root.remove(); resolve("open"); }, 900);
      });
    });
  }

  async function expandHiddenContent() {
    // Click generic aria-expanded controls only when they look like "read more" behavior.
    document.querySelectorAll('[aria-expanded="false"]').forEach((el) => {
      if (!shouldClickExpansionControl(el)) {
        return;
      }
      try {
        el.click();
      } catch (_e) {}
    });

    // Click buttons/links whose visible text suggests expansion.
    document.querySelectorAll("button, [role='button'], a").forEach((el) => {
      if (!shouldClickExpansionControl(el)) {
        return;
      }
      try {
        el.click();
      } catch (_e) {}
    });

    // Give the DOM a moment to update
    await new Promise((resolve) => setTimeout(resolve, 350));
  }

  // Fetch from Greenhouse's public boards API and return a synthetic JSON-LD JobPosting.
  // Works for both job-boards.greenhouse.io (new React SPA, zero JSON-LD in DOM) and
  // the classic boards.greenhouse.io domain.
  const GREENHOUSE_TIMEOUT_MS = 5000;

  async function fetchGreenhouseJobData(url) {
    const match = url.match(/(?:job-boards|boards)\.greenhouse\.io\/([^/?#]+)\/jobs\/(\d+)/);
    if (!match) return null;
    const [, board, jobId] = match;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), GREENHOUSE_TIMEOUT_MS);
    try {
      const res = await fetch(`https://boards-api.greenhouse.io/v1/boards/${board}/jobs/${jobId}`, {
        headers: { Accept: 'application/json' },
        signal: controller.signal
      });
      clearTimeout(timer);
      if (!res.ok) return null;
      const data = await res.json();
      const posting = { '@type': 'JobPosting', title: data.title || null, description: data.content || '' };
      if (data.location?.name) {
        posting.jobLocation = { '@type': 'Place', address: { '@type': 'PostalAddress', addressLocality: data.location.name } };
      }
      // pay_input_ranges is available for postings that expose compensation publicly.
      if (data.pay_input_ranges?.length) {
        const r = data.pay_input_ranges[0];
        posting.baseSalary = {
          '@type': 'MonetaryAmount',
          currency: r.currency_type || 'USD',
          value: { '@type': 'QuantitativeValue', minValue: r.min_cents ? r.min_cents / 100 : null, maxValue: r.max_cents ? r.max_cents / 100 : null, unitText: 'YEAR' }
        };
      }
      return { posting, rawTitle: data.title || null };
    } catch (_) {
      clearTimeout(timer);
      return null;
    }
  }

  async function capturePage(win, doc) {
    // Remove any preflight dialog left over from a previous interrupted capture.
    // In world:MAIN the injected script persists across calls, so a stale dialog
    // from a prior run would otherwise end up in body.innerText.
    const stale = doc.getElementById("jobhunt-capture-preflight");
    if (stale) stale.remove();

    await expandHiddenContent();

    const url = win.location.href;
    let pageTitle = doc.title || url;
    const structuredData = collectStructuredData(doc);

    // Greenhouse SPA pages (job-boards.greenhouse.io) don't embed JSON-LD in the HTML —
    // the structured data is rendered client-side after our capture runs. Fetch from the
    // public Boards API instead and inject a synthetic JSON-LD JobPosting so the
    // extraction pipeline gets the full description and salary.
    const ghData = await fetchGreenhouseJobData(url);
    if (ghData) {
      structuredData.push(ghData.posting);
      // The page title on job-boards.greenhouse.io is "Job Application for …" not the
      // job title itself; the API returns the canonical job title.
      if (ghData.rawTitle && /^Job Application\b/i.test(pageTitle)) {
        pageTitle = ghData.rawTitle;
      }
    }

    // BambooHR career SPAs (*.bamboohr.com/careers/{id}) often leave document.title as
    // the generic "BambooHR" string even after the job content has rendered. Use the
    // first H1 in the main content area as a more reliable job title.
    if (/\.bamboohr\.com\/careers\//.test(url) && (!pageTitle || pageTitle === 'BambooHR')) {
      const h1 = doc.querySelector('main h1, [role="main"] h1, h1');
      const h1Text = h1 ? h1.textContent.trim() : '';
      if (h1Text && h1Text !== 'BambooHR') pageTitle = h1Text;
    }

    const payload = {
      schema_version: 1,
      captured_at: new Date().toISOString(),
      url,
      canonical_url: collectCanonicalUrl(doc),
      page_title: pageTitle,
      selected_text: collectSelectedText(win),
      visible_text: collectVisibleText(doc, win),
      // `structured_data` (array) is kept for the preflight stats and as a fallback; also send the
      // server's preferred typed field `structured_data_json` so Greenhouse-enriched JSON-LD reaches
      // ingestion via the explicit contract, not just the raw-body fallback (TASK-437/442).
      structured_data: structuredData,
      structured_data_json: structuredData.length ? JSON.stringify(structuredData) : null,
      user_note: "",
      source: {
        extension_version: (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.getManifest)
          ? chrome.runtime.getManifest().version
          : "unknown",
        browser: "chrome"
      }
    };
    payload.preflight = capturePreflight(payload);
    return payload;
  }

  globalThis.jobhuntCapture = {
    capturePage,
    capturePreflight,
    showCapturePreflight,
    collectStructuredData,
    collectVisibleText,
    collectSelectedText,
    collectCanonicalUrl
  };
})();
