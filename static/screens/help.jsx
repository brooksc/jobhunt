// Jobhunt — Help documentation

const HELP_SECTIONS = [
  {
    title: "Start here",
    body: [
      "Jobhunt is a local-first job tracker. The Chrome extension captures job pages, the local service stores them in SQLite, and the app helps you extract structured fields, track follow-ups, review data quality, and export your pipeline.",
      "A normal workflow is: capture jobs from the browser, run AI extraction, review Data Quality, move promising jobs through statuses, and use Needs Action for follow-ups.",
    ],
  },
  {
    title: "Initial setup",
    items: [
      "Start the local service with npm start, then open the app URL shown by the server.",
      "Install the unpacked Chrome extension from the extension directory and keep the local service running while capturing pages.",
      "Open Settings to configure the LLM provider, model, preferred locations, work arrangements, follow-up defaults, and resume text for fit scoring.",
      "Use Test connection in Settings before queueing a large extraction batch.",
    ],
  },
  {
    title: "Capturing jobs",
    items: [
      "Open a job posting in Chrome or Chromium and click the Jobhunt extension button.",
      "If the service is unavailable, the extension queues the capture and retries later.",
      "Captured jobs appear in Jobs. The sidebar Extension status shows whether captures have happened recently.",
      "If a posting is poorly captured, open the job detail panel and inspect Capture diagnostics, selected text, structured data, and raw source fields.",
    ],
  },
  {
    title: "Jobs",
    items: [
      "Use the Jobs table to search, filter, sort, select rows, bulk-change status, queue AI work, compare selected jobs, and export CSV.",
      "Open a row to view details, edit extracted fields, inspect timeline events, read captured descriptions, view raw diagnostics, re-run AI, copy debug data, or mark a job unavailable.",
      "Saved views in the sidebar let you return to common filters such as active applications, matching remote jobs, and recent captures.",
      "Press Command-K or Control-K from anywhere in the app to jump to Jobs search.",
    ],
  },
  {
    title: "AI extraction",
    items: [
      "Run AI extraction from Dashboard, Jobs, or the LLM Queue after your provider and model are configured.",
      "Use Full extraction when the page needs complete parsing, Missing fields only for cleanup, and Fit score only after adding or changing your resume.",
      "The LLM Queue shows outstanding, running, failed, and completed requests with attempt history and retry controls.",
      "Failed attempts are durable. Settings can enable LLM debug logging for deeper troubleshooting.",
    ],
  },
  {
    title: "Data Quality",
    items: [
      "Data Quality groups active jobs with missing or suspect fields, stale captures, short captures, failed extraction, and AI-only gaps.",
      "Use Browser recapture checklist for problems that likely need a better capture. Use AI re-run checklist for records that can probably be fixed by extraction.",
      "Open visible jobs to review them one at a time, select them in Jobs for bulk work, or dismiss visible rows after you have reviewed the gap.",
      "Reviewed jobs remain available under the Reviewed filter so you can undo a dismissal.",
    ],
  },
  {
    title: "Needs Action",
    items: [
      "Needs Action collects follow-ups due today or overdue.",
      "Follow-up dates are created from job detail actions and use the default interval configured in Settings.",
      "Complete actions from the list when you have sent an email, applied, checked a status page, or intentionally deferred the job.",
    ],
  },
  {
    title: "Sites",
    items: [
      "Use Sites to track company or job-board pages that should be reviewed periodically even when no specific posting is captured.",
      "Add a site URL from the Sites page. New sites inherit the review interval from Settings.",
      "Reviewing a site updates its last-reviewed and next-review dates so recurring prospecting does not disappear from the workflow.",
    ],
  },
  {
    title: "Duplicates",
    items: [
      "Duplicates groups captures that look like the same job posting.",
      "Compare a group to decide which record to keep, merge, archive, or ignore.",
      "Use duplicate review after large capture sessions or after retry queues flush several saved postings at once.",
    ],
  },
  {
    title: "Settings and data",
    items: [
      "Settings controls the local service status, extension status, availability automation, LLM provider, resume text, location filtering, defaults, export, and local paths.",
      "The app stores runtime data under the config directory shown in Settings unless JOBHUNT_CONFIG_DIR or JOBHUNT_DB_PATH is set.",
      "Export CSV from Settings or Jobs when you need a spreadsheet copy of the current job table.",
    ],
  },
  {
    title: "Troubleshooting",
    items: [
      "No new captures: confirm the local service is running, reload the extension, and check the sidebar Extension status.",
      "Extraction does not run: check Settings provider details, load or select a model, run Test connection, then inspect LLM Queue failures.",
      "Fields look wrong: inspect Capture diagnostics, re-run AI, or recapture the page with more visible job text selected.",
      "Availability checks mark jobs unavailable: open the source URL from job details and restore the status manually if the site blocks automated checks.",
      "UI looks stale: use Reload in the top bar or restart the local service.",
    ],
  },
];

function HelpPage() {
  return (
    <div className="jh-help">
      <div className="jh-help__intro">
        <div>
          <h1>Help</h1>
          <p>Operational guide for running the local job-search workflow end to end.</p>
        </div>
        <div className="jh-help__quick">
          <span><Icon.Briefcase size={12} />Capture</span>
          <span><Icon.Sparkles size={12} />Extract</span>
          <span><Icon.AlertTriangle size={12} />Review</span>
          <span><Icon.Bell size={12} />Follow up</span>
        </div>
      </div>

      <div className="jh-help__grid">
        {HELP_SECTIONS.map((section) => (
          <section key={section.title} className="jh-help__section">
            <h2>{section.title}</h2>
            {section.body?.map((text) => <p key={text}>{text}</p>)}
            {section.items && (
              <ul>
                {section.items.map((item) => <li key={item}>{item}</li>)}
              </ul>
            )}
          </section>
        ))}
      </div>
    </div>
  );
}

Object.assign(window, { HelpPage });
