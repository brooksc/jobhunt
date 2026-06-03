// Jobhunt — icons + small primitives.
// Inline SVGs with currentColor. 14px default.

const I = ({ d, size = 14, fill = "none", stroke = "currentColor", sw = 1.6, style }) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill={fill} stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round" style={style}>
    {typeof d === "string" ? <path d={d} /> : d}
  </svg>
);

const Icon = {
  Briefcase: (p) => <I {...p} d={<>
    <rect x="2" y="5" width="12" height="9" rx="1.2" />
    <path d="M5.5 5V3.6c0-.6.4-1 1-1h3c.6 0 1 .4 1 1V5" />
    <path d="M2 9h12" />
  </>} />,
  Bell: (p) => <I {...p} d={<>
    <path d="M4 11h8l-1.2-1.6V7c0-1.7-1.3-3-3-3s-3 1.3-3 3v2.4z" />
    <path d="M7 13h2" />
  </>} />,
  Globe: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="6" />
    <path d="M2 8h12M8 2c2 2.2 2 9.8 0 12M8 2C6 4.2 6 11.8 8 14" />
  </>} />,
  Copy: (p) => <I {...p} d={<>
    <rect x="5" y="5" width="8" height="8" rx="1" />
    <path d="M3 11V4c0-.6.4-1 1-1h7" />
  </>} />,
  Settings: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="1.8" />
    <path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4" />
  </>} />,
  Home: (p) => <I {...p} d="M2.5 8L8 3l5.5 5M4 7.5V13h8V7.5" />,
  Search: (p) => <I {...p} d={<>
    <circle cx="7" cy="7" r="4.2" />
    <path d="M10.2 10.2L13 13" />
  </>} />,
  Filter: (p) => <I {...p} d="M2.5 3.5h11l-4 5v4l-3 1.5v-5.5z" />,
  ChevronDown: (p) => <I {...p} d="M3.5 5.5L8 10l4.5-4.5" />,
  ChevronRight: (p) => <I {...p} d="M6 3.5L10.5 8 6 12.5" />,
  ChevronLeft: (p) => <I {...p} d="M10 3.5L5.5 8 10 12.5" />,
  ChevronsUpDown: (p) => <I {...p} d="M4.5 6L8 3l3.5 3M4.5 10L8 13l3.5-3" />,
  ArrowUpDown: (p) => <I {...p} d="M5 11l-1.5 1.5L2 11M3.5 12.5V3.5M11 5l1.5-1.5L14 5M12.5 3.5v9" />,
  Plus: (p) => <I {...p} d="M8 3v10M3 8h10" />,
  X: (p) => <I {...p} d="M4 4l8 8M12 4l-8 8" />,
  Check: (p) => <I {...p} d="M3.5 8.5L6 11l6.5-6.5" />,
  More: (p) => <I {...p} d={<>
    <circle cx="3" cy="8" r=".9" fill="currentColor" stroke="none" />
    <circle cx="8" cy="8" r=".9" fill="currentColor" stroke="none" />
    <circle cx="13" cy="8" r=".9" fill="currentColor" stroke="none" />
  </>} />,
  External: (p) => <I {...p} d="M6.5 3H3v10h10V9.5M9.5 2.5H13.5V6.5M13.5 2.5L8 8" />,
  Refresh: (p) => <I {...p} d={<>
    <path d="M2.5 8c0-3 2.5-5.5 5.5-5.5 2 0 3.8 1.2 4.7 2.8" />
    <path d="M11.5 2.5v3h3M13.5 8c0 3-2.5 5.5-5.5 5.5-2 0-3.8-1.2-4.7-2.8" />
    <path d="M4.5 13.5v-3h-3" />
  </>} />,
  Archive: (p) => <I {...p} d={<>
    <rect x="2" y="3" width="12" height="3" rx=".7" />
    <path d="M3 6v6.5c0 .5.4.9.9.9h8.2c.5 0 .9-.4.9-.9V6" />
    <path d="M6.5 9h3" />
  </>} />,
  Note: (p) => <I {...p} d={<>
    <path d="M3 3.5h9V13l-3-2.5H4c-.6 0-1-.4-1-1z" />
    <path d="M5.5 6.5h5M5.5 8.5h3" />
  </>} />,
  Pencil: (p) => <I {...p} d={<>
    <path d="M10.5 2.5l3 3-7.5 7.5H3v-3z" />
    <path d="M8.5 4.5l3 3" />
  </>} />,
  Calendar: (p) => <I {...p} d={<>
    <rect x="2.5" y="4" width="11" height="9" rx="1" />
    <path d="M2.5 7h11M5 2.5v3M11 2.5v3" />
  </>} />,
  Clock: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M8 5v3l2 1.5" />
  </>} />,
  Snooze: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="5.5" />
    <path d="M6 6h3.5L6 10h3.5" />
  </>} />,
  Database: (p) => <I {...p} d={<>
    <ellipse cx="8" cy="3.5" rx="5" ry="1.5" />
    <path d="M3 3.5v9c0 .8 2.2 1.5 5 1.5s5-.7 5-1.5v-9" />
    <path d="M3 8c0 .8 2.2 1.5 5 1.5s5-.7 5-1.5" />
  </>} />,
  Sun: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="2.5" />
    <path d="M8 1.5v1.5M8 13v1.5M1.5 8h1.5M13 8h1.5M3.4 3.4l1 1M11.6 11.6l1 1M3.4 12.6l1-1M11.6 4.4l1-1" />
  </>} />,
  Moon: (p) => <I {...p} d="M13 9.5A5.5 5.5 0 016.5 3a5.5 5.5 0 100 11 5.5 5.5 0 006.5-4.5z" />,
  Pin: (p) => <I {...p} d={<>
    <path d="M6 2.5h4l-.5 3 2 2.5h-7l2-2.5z" />
    <path d="M8 8v5" />
  </>} />,
  Merge: (p) => <I {...p} d="M4 2.5v3c0 1.5 1 2.5 2.5 2.5h3c1.5 0 2.5 1 2.5 2.5v3M12 6L10 3.5M12 6l-2 2.5" />,
  Split: (p) => <I {...p} d="M4 13.5v-3c0-1.5 1-2.5 2.5-2.5h3c1.5 0 2.5-1 2.5-2.5v-3M12 10l-2 2.5M12 10l-2-2.5" />,
  Tag: (p) => <I {...p} d={<>
    <path d="M2.5 7.5V3h4.5L13.5 9.5l-4.5 4.5z" />
    <circle cx="5" cy="5.5" r=".7" fill="currentColor" stroke="none" />
  </>} />,
  Money: (p) => <I {...p} d={<>
    <rect x="2" y="4" width="12" height="8" rx="1" />
    <circle cx="8" cy="8" r="1.5" />
    <path d="M4 6v4M12 6v4" />
  </>} />,
  Sparkles: (p) => <I {...p} d="M8 2.5l1 2.5 2.5 1-2.5 1-1 2.5-1-2.5-2.5-1 2.5-1z M12 9l.6 1.4 1.4.6-1.4.6L12 13l-.6-1.4-1.4-.6 1.4-.6z" />,
  ArrowRight: (p) => <I {...p} d="M3 8h10M9.5 4.5L13 8l-3.5 3.5" />,
  Inbox: (p) => <I {...p} d={<>
    <path d="M2.5 9.5L4 4h8l1.5 5.5v3h-11z" />
    <path d="M2.5 9.5h3l.8 1.5h3.4l.8-1.5h3" />
  </>} />,
  Trash: (p) => <I {...p} d={<>
    <path d="M3 4h10M5 4V3a1 1 0 011-1h4a1 1 0 011 1v1M5.5 7v4M10.5 7v4" />
    <path d="M4 4l.6 8.5c0 .8.6 1 1 1h4.8c.5 0 .9-.2 1-1L12 4" />
  </>} />,
  AlertTriangle: (p) => <I {...p} d="M8 2.5l6 11h-12zM8 6.5v3M8 11.2v.3" />,
  Loader: (p) => <I {...p} d="M8 2.5v2.5M8 11v2.5M2.5 8h2.5M11 8h2.5M3.8 3.8l1.7 1.7M10.5 10.5l1.7 1.7M3.8 12.2l1.7-1.7M10.5 5.5l1.7-1.7" />,
  Eye: (p) => <I {...p} d={<>
    <path d="M1.5 8s2.3-4.5 6.5-4.5S14.5 8 14.5 8s-2.3 4.5-6.5 4.5S1.5 8 1.5 8z" />
    <circle cx="8" cy="8" r="1.8" />
  </>} />,
  Link: (p) => <I {...p} d="M9 7l3-3a2.5 2.5 0 113.5 3.5l-3 3M7 9l-3 3A2.5 2.5 0 11.5 8.5l3-3M6 10l4-4" />,
  Help: (p) => <I {...p} d={<>
    <circle cx="8" cy="8" r="6" />
    <path d="M6.3 6.2c.2-1 1-1.7 2.1-1.7 1.2 0 2.1.8 2.1 1.9 0 .8-.4 1.3-1.2 1.9-.7.5-1 .9-1 1.7" />
    <path d="M8.3 12h.1" />
  </>} />,
};

// ── primitives ──

const Chip = ({ status, children, className = "" }) => (
  <span className={`jh-chip ${className}`} data-status={status}>
    <span className="dot"></span>
    {children}
  </span>
);

const StatusChip = ({ value }) => {
  const labels = {
    saved: "Saved",
    applied: "Applied",
    interview: "Interview",
    offer: "Offer",
    rejected: "Rejected",
    archived: "Archived",
    not_available: "Not available",
    duplicate: "Duplicate",
  };
  return <Chip status={value}>{labels[value] || value}</Chip>;
};

const ExtractionChip = ({ ext }) => {
  if (!ext) return <span className="jh-ex" data-state="pending"><span className="dot"></span>—</span>;
  if (ext.status === "ok") return <span className="jh-ex" data-state="ok"><span className="dot"></span>ok</span>;
  if (ext.status === "pending") return <span className="jh-ex" data-state="pending"><span className="dot"></span>pending</span>;
  return <span className="jh-ex" data-state="fail"><span className="dot"></span>failed</span>;
};

const CoLogo = ({ name, url }) => {
  const co = (window.JH_COMPANIES || {})[name];
  const mono = (co && co.mono) || (name ? name.slice(0, 1).toUpperCase() : "?");
  let faviconUrl = null;
  try { if (url) faviconUrl = new URL(url).origin + "/favicon.ico"; } catch (e) {}
  return (
    <span className="jh-comp__mark">
      {faviconUrl
        ? <img src={faviconUrl} width={12} height={12} style={{ display: "block", borderRadius: 2 }}
            onError={(e) => { e.currentTarget.outerHTML = mono; }} />
        : mono}
    </span>
  );
};

const CompanyCell = ({ name, url }) => (
  <span className="jh-comp"><CoLogo name={name} url={url} /><span>{name}</span></span>
);

const Btn = React.forwardRef(({ kind = "default", size, icon, children, active, ...rest }, ref) => {
  const cls = ["jh-btn"];
  if (kind === "ghost") cls.push("jh-btn--ghost");
  if (kind === "accent") cls.push("jh-btn--accent");
  if (kind === "danger") cls.push("jh-btn--danger");
  if (size === "sm") cls.push("jh-btn--sm");
  if (!children) cls.push("jh-btn--icon");
  return (
    <button ref={ref} {...rest} className={cls.join(" ") + (rest.className ? " " + rest.className : "")} aria-pressed={active}>
      {icon}{children}
    </button>
  );
});

const Kbd = ({ children }) => <span className="kbd">{children}</span>;

// salary formatter
function fmtSalary(j) {
  if (!j.salaryMin && !j.salaryMax) return j.salaryNote || "—";
  const sym = { USD: "$", GBP: "£", EUR: "€", CAD: "C$", AUD: "A$" }[j.currency] || (j.currency ? j.currency + " " : "");
  const k = (n) => n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
  if (j.salaryMin && j.salaryMax) return `${sym}${k(j.salaryMin)}–${k(j.salaryMax)}`;
  return `${sym}${k(j.salaryMin || j.salaryMax)}`;
}

// relative-ish date — relative for ≤7d, otherwise short
function fmtCaptured(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  const now = new Date();
  const ms = now - d;
  const min = Math.floor(ms / 60000);
  const h = Math.floor(min / 60);
  const days = Math.floor(h / 24);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  if (h < 24) return `${h}h ago`;
  if (days <= 7) return `${days}d ago`;
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function fmtDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

function fmtDateTime(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + " · " + d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
}

function daysFrom(iso) {
  if (!iso) return null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const d = new Date(iso + "T00:00:00");
  d.setHours(0, 0, 0, 0);
  return Math.round((d - today) / 86400000);
}

function dueState(iso) {
  const n = daysFrom(iso);
  if (n === null) return "future";
  if (n < 0) return "overdue";
  if (n === 0) return "today";
  if (n <= 3) return "soon";
  return "future";
}

function dueLabel(iso) {
  const n = daysFrom(iso);
  if (n === null) return "—";
  if (n < -1) return `${Math.abs(n)}d overdue`;
  if (n === -1) return "1d overdue";
  if (n === 0) return "Today";
  if (n === 1) return "Tomorrow";
  return `in ${n}d`;
}

// AppDialog - general-purpose modal with title + content + action buttons
// Props: title, onClose, children, actions=[{label, kind, onClick, disabled}]
function AppDialog({ title, onClose, children, actions = [], maxWidth = 400 }) {
  const dialogRef = React.useRef(null);

  // Close on Escape
  React.useEffect(() => {
    const handler = (e) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [onClose]);

  // Focus trap
  React.useEffect(() => {
    const modal = dialogRef.current;
    if (!modal) return;
    const focusable = modal.querySelectorAll('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])');
    if (focusable.length) focusable[0].focus();
    const trapFocus = (e) => {
      if (e.key !== "Tab") return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey ? document.activeElement === first : document.activeElement === last) {
        e.preventDefault();
        (e.shiftKey ? last : first).focus();
      }
    };
    modal.addEventListener("keydown", trapFocus);
    return () => modal.removeEventListener("keydown", trapFocus);
  }, []);

  // jh-root ensures CSS resets (outline:0, font, etc.) apply even when the modal
  // is rendered outside the main app root (e.g. first-run bootstrap).
  const rootTheme = document.querySelector('.jh-root')?.dataset.theme || 'auto';
  return (
    <div className={`jh-root`} data-theme={rootTheme}>
    <div className="jh-modal" role="dialog" aria-modal="true" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div ref={dialogRef} className="jh-modal__card" style={{ maxWidth }}>
        <div className="jh-modal__head">
          <h2>{title}</h2>
        </div>
        <div className="jh-modal__body">{children}</div>
        {actions.length > 0 && (
          <div className="jh-modal__actions">
            {actions.map((a, i) => (
              <Btn key={i} size="sm" kind={a.kind || "default"} onClick={a.onClick} disabled={a.disabled}>{a.label}</Btn>
            ))}
          </div>
        )}
      </div>
    </div>
    </div>
  );
}

// AppTextInputDialog - single text input modal
// Props: title, placeholder, defaultValue, multiline, onConfirm(value), onClose
function AppTextInputDialog({ title, placeholder = "", defaultValue = "", multiline = false, onConfirm, onClose }) {
  const [value, setValue] = React.useState(defaultValue);
  const inputRef = React.useRef(null);
  React.useEffect(() => { inputRef.current?.focus(); }, []);

  const handleSubmit = () => { if (value.trim()) onConfirm(value.trim()); };

  React.useEffect(() => {
    const handler = (e) => {
      if (e.key === "Escape") { onClose(); return; }
      if (e.key === "Enter" && (multiline ? e.metaKey || e.ctrlKey : true)) { e.preventDefault(); handleSubmit(); }
    };
    document.addEventListener("keydown", handler);
    return () => document.removeEventListener("keydown", handler);
  }, [value]);

  return (
    <AppDialog title={title} onClose={onClose} actions={[
      { label: "Cancel", kind: "ghost", onClick: onClose },
      { label: "Confirm", kind: "accent", onClick: handleSubmit, disabled: !value.trim() },
    ]}>
      {multiline ? (
        <textarea ref={inputRef} className="jh-textarea" style={{ width: "100%", minHeight: 80, resize: "vertical" }}
          placeholder={placeholder} value={value} onChange={e => setValue(e.target.value)} />
      ) : (
        <input ref={inputRef} type="text" className="jh-input" style={{ width: "100%" }}
          placeholder={placeholder} value={value} onChange={e => setValue(e.target.value)} />
      )}
      {multiline && <div style={{ fontSize: 11, color: "var(--fg-faint)", marginTop: 4 }}>Cmd+Enter to submit</div>}
    </AppDialog>
  );
}

// AppSelectDialog - choose from a list of options
// Props: title, options=[{value, label}], onConfirm(value), onClose
function AppSelectDialog({ title, options, onConfirm, onClose }) {
  const [selected, setSelected] = React.useState(options[0]?.value);
  return (
    <AppDialog title={title} onClose={onClose} actions={[
      { label: "Cancel", kind: "ghost", onClick: onClose },
      { label: "Confirm", kind: "accent", onClick: () => selected && onConfirm(selected) },
    ]}>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {options.map(opt => (
          <label key={opt.value} style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 0", cursor: "pointer" }}>
            <input type="radio" name="dialog-select" value={opt.value} checked={selected === opt.value}
              onChange={() => setSelected(opt.value)} />
            {opt.label}
          </label>
        ))}
      </div>
    </AppDialog>
  );
}

// Toast system - expose window.JH_TOAST.show(message, kind='success'|'error'|'warn'|'info')
let _toastSetState = null;
let _toastId = 0;
const JH_TOAST = {
  show(message, kind = "success") {
    if (!_toastSetState) return;
    const id = ++_toastId;
    _toastSetState(prev => [...prev, { id, message, kind }]);
    setTimeout(() => {
      _toastSetState(prev => prev.filter(t => t.id !== id));
    }, 3500);
  }
};

function ToastContainer() {
  const [toasts, setToasts] = React.useState([]);
  React.useEffect(() => { _toastSetState = setToasts; return () => { _toastSetState = null; }; }, []);
  if (!toasts.length) return null;
  return (
    <div className="jh-toast-container" role="log" aria-live="polite">
      {toasts.map(t => (
        <div key={t.id} className="jh-toast" data-kind={t.kind}>
          {t.kind === "success" && <Icon.Check size={13} />}
          {t.kind === "error" && <Icon.AlertTriangle size={13} />}
          <span>{t.message}</span>
        </div>
      ))}
    </div>
  );
}

function StarRating({ value, onChange, size = 14, readonly = false }) {
  const [hovered, setHovered] = React.useState(null);
  const display = hovered ?? value ?? 0;
  return (
    <span className="jh-stars" style={{ display: "inline-flex", gap: 1 }}
      onMouseLeave={readonly ? undefined : () => setHovered(null)}>
      {[1, 2, 3, 4, 5].map(n => (
        <button
          key={n}
          type="button"
          className="jh-star"
          data-filled={display >= n ? "true" : "false"}
          aria-label={`${n} star${n !== 1 ? "s" : ""}`}
          onClick={readonly ? undefined : () => onChange(value === n ? null : n)}
          onMouseEnter={readonly ? undefined : () => setHovered(n)}
          disabled={readonly}
          style={{
            background: "none", border: "none", padding: 0, cursor: readonly ? "default" : "pointer",
            color: display >= n ? "var(--accent, #f59e0b)" : "var(--fg-faint)",
            fontSize: size,
          }}
        >★</button>
      ))}
    </span>
  );
}

function LocationPicker({ preferredMetros, setPreferredMetros, preferredLocations, setPreferredLocations, filterEnabled, setFilterEnabled, allowRemote, setAllowRemote, allowHybrid, setAllowHybrid, allowOnsite, setAllowOnsite }) {
  const metros = window.JH_METROS || {};

  // Parse "wa:seattle,ca:bay-area" into a Set of "wa:seattle" tokens
  function parseMetroSet(str) {
    return new Set((str || '').split(',').map(t => t.trim()).filter(Boolean));
  }

  // Toggle a single metro in the CSV string
  function toggleMetro(state, metroId) {
    const key = `${state}:${metroId}`;
    const set = parseMetroSet(preferredMetros);
    if (set.has(key)) set.delete(key); else set.add(key);
    setPreferredMetros([...set].join(','));
  }

  // Toggle all metros in a state
  function toggleState(state) {
    const stateMetros = Object.keys(metros[state]?.metros || {});
    const set = parseMetroSet(preferredMetros);
    const allSelected = stateMetros.every(m => set.has(`${state}:${m}`));
    if (allSelected) {
      stateMetros.forEach(m => set.delete(`${state}:${m}`));
    } else {
      stateMetros.forEach(m => set.add(`${state}:${m}`));
    }
    setPreferredMetros([...set].join(','));
  }

  // Build preview city list
  function getPreviewCities() {
    const set = parseMetroSet(preferredMetros);
    const cities = new Set();
    for (const token of set) {
      const [state, metroId] = token.split(':');
      const metroData = metros[state]?.metros?.[metroId];
      if (metroData) metroData.cities.forEach(c => cities.add(c));
    }
    (preferredLocations || '').split(',').forEach(c => { const t = c.trim(); if (t) cities.add(t); });
    return [...cities].sort();
  }

  const metroSet = parseMetroSet(preferredMetros);
  const sortedStates = Object.entries(metros).sort((a, b) => a[1].label.localeCompare(b[1].label));
  const previewCities = filterEnabled ? getPreviewCities() : [];
  const disabled = !filterEnabled;

  const checkRow = { display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer', userSelect: 'none', padding: '2px 0' };
  const faded = { opacity: disabled ? 0.4 : 1, pointerEvents: disabled ? 'none' : 'auto' };

  return (
    <div>
      {/* Open to relocation */}
      <label style={{ ...checkRow, marginBottom: 14, fontWeight: 500 }}>
        <input type="checkbox" checked={!filterEnabled} onChange={e => setFilterEnabled(!e.target.checked)} />
        Open to relocation — don't filter by location
      </label>

      <div style={faded}>
        {/* Work arrangement */}
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-mute)', marginBottom: 6 }}>Work arrangement</div>
          <div style={{ display: 'flex', gap: 20 }}>
            <label style={checkRow}><input type="checkbox" checked={allowRemote} onChange={e => setAllowRemote(e.target.checked)} /> Remote</label>
            <label style={checkRow}><input type="checkbox" checked={allowHybrid} onChange={e => setAllowHybrid(e.target.checked)} /> Hybrid</label>
            <label style={checkRow}><input type="checkbox" checked={allowOnsite} onChange={e => setAllowOnsite(e.target.checked)} /> In-office</label>
          </div>
        </div>

        {/* State/metro picker */}
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-mute)', marginBottom: 6 }}>Preferred regions</div>
          <div style={{ maxHeight: 220, overflowY: 'auto', border: '1px solid var(--border)', borderRadius: 6, padding: '6px 10px', background: 'var(--bg)' }}>
            {sortedStates.map(([stateKey, stateData]) => {
              const stateMetros = Object.entries(stateData.metros);
              const selectedCount = stateMetros.filter(([mId]) => metroSet.has(`${stateKey}:${mId}`)).length;
              const allSelected = selectedCount === stateMetros.length;
              const someSelected = selectedCount > 0 && !allSelected;
              return (
                <StateRow key={stateKey} stateKey={stateKey} stateData={stateData} stateMetros={stateMetros}
                  allSelected={allSelected} someSelected={someSelected} metroSet={metroSet}
                  onToggleState={() => toggleState(stateKey)} onToggleMetro={(mId) => toggleMetro(stateKey, mId)} />
              );
            })}
          </div>
        </div>

        {/* Manual additions */}
        <div style={{ marginBottom: 14 }}>
          <div style={{ fontSize: 11, fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.05em', color: 'var(--fg-mute)', marginBottom: 4 }}>Additional locations <span style={{ fontWeight: 400, textTransform: 'none', letterSpacing: 0 }}>(cities not in the list above)</span></div>
          <input
            value={preferredLocations}
            onChange={e => setPreferredLocations(e.target.value)}
            placeholder="e.g. Boise, ID, Spokane, WA"
            style={{ width: '100%', padding: '6px 8px', borderRadius: 5, border: '1px solid var(--border)', background: 'var(--bg)', color: 'var(--fg)', fontSize: 12, boxSizing: 'border-box' }}
          />
        </div>

        {/* Preview */}
        {previewCities.length > 0 && (
          <div style={{ fontSize: 11, color: 'var(--fg-faint)', lineHeight: 1.4 }}>
            <span style={{ fontWeight: 600, color: 'var(--fg-mute)' }}>Effective filter: </span>
            {previewCities.slice(0, 12).join(', ')}{previewCities.length > 12 ? ` + ${previewCities.length - 12} more` : ''}
          </div>
        )}
        {filterEnabled && previewCities.length === 0 && (
          <div style={{ fontSize: 11, color: 'var(--fg-faint)' }}>No regions selected — all locations will match.</div>
        )}
      </div>
    </div>
  );
}

function StateRow({ stateKey, stateData, stateMetros, allSelected, someSelected, metroSet, onToggleState, onToggleMetro }) {
  const cbRef = React.useRef(null);
  React.useEffect(() => {
    if (cbRef.current) cbRef.current.indeterminate = someSelected;
  }, [someSelected]);

  const checkRow = { display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, cursor: 'pointer', userSelect: 'none', padding: '2px 0' };

  return (
    <div style={{ marginBottom: 2 }}>
      <label style={{ ...checkRow, fontWeight: 500 }}>
        <input ref={cbRef} type="checkbox" checked={allSelected} onChange={onToggleState} />
        {stateData.label}
      </label>
      {(allSelected || someSelected) && (
        <div style={{ marginLeft: 22, marginBottom: 4 }}>
          {stateMetros.map(([metroId, metroData]) => (
            <label key={metroId} style={{ ...checkRow, fontSize: 12, color: 'var(--fg-mute)' }}>
              <input type="checkbox" checked={metroSet.has(`${stateKey}:${metroId}`)} onChange={() => onToggleMetro(metroId)} />
              {metroData.label}
            </label>
          ))}
        </div>
      )}
    </div>
  );
}

function Metric({ label, value, delta, warn, emphasis }) {
  return (
    <div className="jh-metric" style={emphasis ? { borderColor: 'var(--accent-border)', background: 'var(--accent-bg)' } : undefined}>
      <span className="jh-metric__label">{label}</span>
      <span className="jh-metric__value">{value}</span>
      <span className="jh-metric__delta" style={warn ? { color: 'var(--st-rejected)' } : undefined}>{delta}</span>
    </div>
  );
}

Object.assign(window, {
  Icon, Chip, StatusChip, ExtractionChip, CoLogo, CompanyCell, Btn, Kbd,
  fmtSalary, fmtCaptured, fmtDate, fmtDateTime, daysFrom, dueState, dueLabel,
  AppDialog, AppTextInputDialog, AppSelectDialog, ToastContainer, JH_TOAST,
  StarRating, LocationPicker, Metric,
});
