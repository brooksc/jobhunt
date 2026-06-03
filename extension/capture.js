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

    if (isLikelyLayoutElement(node)) {
      return false;
    }

    return true;
  }

  function collectStructuredData(doc) {
    return Array.from(doc.querySelectorAll('script[type="application/ld+json"]'))
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

    // Supplement with Next.js RSC data when the DOM text is sparse.
    // Some Next.js job pages (e.g. Cribl) bail out to client-side rendering and
    // put the full job description in __next_f payload scripts rather than the DOM.
    const nextjsText = win ? collectNextJSText(win) : "";
    if (nextjsText && nextjsText.length > combined.length / 2) {
      return `${combined}\n\n---\n\n${nextjsText}`;
    }

    return combined;
  }

  function collectSelectedText(win) {
    const selection = win.getSelection ? win.getSelection() : null;
    return selection ? selection.toString().trim() : "";
  }

  function collectNextJSText(win) {
    // Extract text from Next.js RSC data (__next_f). Pages that bail out to
    // client-side rendering (e.g. Cribl, many Next.js job boards) embed the full
    // job description in RSC payload scripts instead of rendering it into the DOM,
    // so body.innerText misses it entirely.
    const arr = win.__next_f;
    if (!Array.isArray(arr)) return '';
    const JOB_SIGNALS = /\$[\d,]+|\b(?:salary|compensation|pay range|requirements|qualifications|responsibilities|experience)\b/i;
    const texts = arr
      .filter(c => Array.isArray(c) && c[0] === 1 && typeof c[1] === 'string')
      // Exclude tiny chunks and very large framework/routing data blobs (>30KB)
      .filter(c => c[1].length >= 500 && c[1].length <= 30000)
      // Only include chunks that look like HTML job description content
      // (must have entity-encoded HTML tags AND job-relevant signals)
      .filter(c => /&lt;[a-z]/.test(c[1]) && JOB_SIGNALS.test(c[1]))
      .map(c => c[1]
        .replace(/&lt;\/?[a-z][^&]{0,50}&gt;/gi, ' ')
        .replace(/&amp;/g, '&')
        .replace(/&nbsp;/g, ' ')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/\s+/g, ' ')
        .trim()
      )
      .filter(s => s.length > 100);
    return [...new Set(texts)].join('\n');
  }

  function collectCanonicalUrl(doc) {
    const canonical = doc.querySelector('link[rel="canonical"]');
    const href = canonical && canonical.href ? canonical.href.trim() : "";
    return href || null;
  }

  function capturePreflight(payload) {
    const visibleText = payload.visible_text || "";
    const selectedText = payload.selected_text || "";
    const structuredData = Array.isArray(payload.structured_data) ? payload.structured_data : [];
    const text = `${payload.page_title || ""}\n${visibleText}\n${selectedText}`;
    return {
      title: Boolean((payload.page_title || "").trim()) || /\b(program|manager|engineer|developer|director|principal|staff)\b/i.test(text),
      location: /\b(remote|hybrid|onsite|on-site|united states|hiring remotely|[A-Z][a-z]+,\s*[A-Z]{2})\b/i.test(text),
      salary: /(?:\$|USD|base salary|pay range|compensation|salary|[0-9]{2,3}k)/i.test(text),
      remote: /\b(remote|hybrid|work from home|telecommute|days?\s*\/\s*week\s+in-office|hiring remotely)\b/i.test(text),
      structuredData: structuredData.length,
      selectedText: Boolean(selectedText.trim()),
      visibleChars: visibleText.length,
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

      const checks = [
        ["Title", preflight.title],
        ["Location", preflight.location],
        ["Salary", preflight.salary],
        ["Remote/work mode", preflight.remote],
      ];
      const rows = checks.map(([label, ok]) => `
        <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;padding:4px 0;">
          <span>${label}</span>
          <strong style="color:${ok ? "#86efac" : "#fca5a5"}">${ok ? "visible" : "missing"}</strong>
        </div>
      `).join("");
      root.innerHTML = `
        <div style="font-weight:700;font-size:14px;margin-bottom:8px;">Jobhunt capture preflight</div>
        ${rows}
        <div style="margin-top:8px;color:#9ca3af;font-size:12px;line-height:1.35;">
          ${preflight.visibleChars.toLocaleString()} visible chars · ${preflight.structuredData} structured item${preflight.structuredData === 1 ? "" : "s"}${preflight.selectedText ? " · selected text" : ""}
        </div>
        <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:12px;">
          <span data-jh-countdown style="font-size:13px;color:#86efac;font-weight:600;">Saving in 5…</span>
          <div style="display:flex;gap:8px;">
            <button data-jh-cancel style="background:transparent;color:#d1d5db;border:1px solid #4b5563;border-radius:6px;padding:6px 10px;cursor:pointer;">Cancel</button>
            <button data-jh-open style="background:transparent;color:#93c5fd;border:1px solid #3b82f6;border-radius:6px;padding:6px 10px;cursor:pointer;">Open in app</button>
          </div>
        </div>
      `;
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
      root.querySelector("[data-jh-open]").addEventListener("click", () => { clearInterval(timer); root.remove(); resolve("open"); });
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

  async function capturePage(win, doc) {
    await expandHiddenContent();
    const payload = {
      schema_version: 1,
      captured_at: new Date().toISOString(),
      url: win.location.href,
      canonical_url: collectCanonicalUrl(doc),
      page_title: doc.title || win.location.href,
      selected_text: collectSelectedText(win),
      visible_text: collectVisibleText(doc, win),
      structured_data: collectStructuredData(doc),
      user_note: "",
      source: {
        extension_version: "0.2.0",
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
