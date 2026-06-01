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

  function collectVisibleText(doc) {
    // Always capture the raw top of the page first.
    // Job boards put key metadata (Remote, salary, seniority, location) in a structured
    // header card that Readability treats as sidebar and strips. The first ~2000 chars of
    // body.innerText almost always covers that card before the nav noise dominates.
    const rawTop = (doc.body && doc.body.innerText ? doc.body.innerText : "").slice(0, 2000).trim();

    if (typeof Readability !== "undefined") {
      try {
        const clone = doc.cloneNode(true);
        const article = new Readability(clone, { charThreshold: 100 }).parse();
        if (article && article.textContent && article.textContent.trim().length > 200) {
          const body = article.textContent.trim();
          // Prepend raw header so metadata badges are never lost, then append the
          // Readability-cleaned body for the full description text.
          return rawTop ? `${rawTop}\n\n---\n\n${body}` : body;
        }
      } catch (_error) {
        // fall through
      }
    }
    // Fallback: raw visible text
    return (doc.body && doc.body.innerText ? doc.body.innerText : "").trim();
  }

  function collectSelectedText(win) {
    const selection = win.getSelection ? win.getSelection() : null;
    return selection ? selection.toString().trim() : "";
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
      location: /\b(remote|hybrid|onsite|on-site|united states|[A-Z][a-z]+,\s*[A-Z]{2})\b/.test(text),
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
        <div style="display:flex;justify-content:flex-end;gap:8px;margin-top:12px;">
          <button data-jh-cancel style="background:transparent;color:#d1d5db;border:1px solid #4b5563;border-radius:6px;padding:6px 10px;cursor:pointer;">Cancel</button>
          <button data-jh-save style="background:#4f46e5;color:white;border:1px solid #6366f1;border-radius:6px;padding:6px 10px;cursor:pointer;">Save job</button>
        </div>
      `;
      document.body.appendChild(root);
      root.querySelector("[data-jh-cancel]").addEventListener("click", () => { root.remove(); resolve(false); });
      root.querySelector("[data-jh-save]").addEventListener("click", () => { root.remove(); resolve(true); });
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
      visible_text: collectVisibleText(doc),
      structured_data: collectStructuredData(doc),
      user_note: "",
      source: {
        extension_version: "0.1.0",
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
