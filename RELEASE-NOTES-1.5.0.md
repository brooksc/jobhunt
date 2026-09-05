## What's new in 1.5.0

### Jobhunt now finds jobs for you

Until now Jobhunt was a filing cabinet: a posting was in the app because you put it there. This release makes it go looking.

Turn on **Automatic search** (Settings → Search), tell it what you're after — job titles to match, titles to exclude, locations allowed and blocked, work arrangement, minimum salary, how old a posting may be — and Jobhunt sweeps public job boards on a schedule and files anything that fits. It never contacts an employer. Companies already in your library become watched boards automatically, and **Search Now** runs a sweep on demand instead of waiting for the schedule. Progress appears on the Dashboard and in a new background-activity status bar, so you can see what it's doing.

Nothing reaches the AI until it has passed every requirement you set, so a sweep of thousands of postings doesn't cost you thousands of extractions — or fill the app with noise.

### Fewer irrelevant jobs, and it tells you why

Postings below your salary floor, or in a work arrangement you've ruled out, are filtered before they're ever scanned instead of being filed and scored first. Where a job is filed anyway for a good reason — an unstated salary, say — the list now shows which criterion it misses, so you can skip it without reading it.

### Salaries and work arrangements are recorded accurately

A year range in prose is no longer mistaken for a pay band. A job's work arrangement is no longer erased just because you'd ruled that arrangement out — which had been quietly hiding those jobs from the "doesn't meet criteria" filter. Existing data is repaired in place.

### Locations from the job board are kept

The board's own location field could previously be overwritten by an office list lifted from the posting's prose. The board's answer now wins, and locations lost to the old behaviour have been restored.

### Fit scoring got more honest

Corrections you record ("I don't have this") now reach newly scored jobs, not just recomputed ones. Quotes drawn from an older version of your résumé are no longer reported as invented.

### Smaller things

- The AI-assistant (MCP) connection survives the app being closed and reopened.
- Icon-only buttons announce themselves properly to VoiceOver instead of reading as unnamed.
- "Find on company site" stays available on aggregator listings.

---

Auto-update: existing 1.4.x users will be offered this build automatically via Sparkle. New installs can download the DMG below.

Requires macOS 15 or later.
