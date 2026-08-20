# Deploying the marketing site

`marketing/` is the public site at **jobhunt-app.com**, hosted on **Cloudflare Pages**, project name
**`jobhunt-app`**. `marketing/` is the site root: `marketing/help/faq.html` serves as `/help/faq`
(Pages strips `.html` with a 308).

**The deploy is manual. Nothing publishes it on push.** There is no GitHub Actions workflow and no
Pages Git integration — a commit to `main` changes nothing that users can see until someone runs the
command below.

```bash
wrangler login                                              # only when the token has expired
wrangler pages deploy marketing --project-name=jobhunt-app
```

The project name and account id are cached in `.wrangler/cache/pages.json` (gitignored), so from a
clean checkout pass `--project-name` explicitly as above.

## This has already gone wrong once — check before you assume

Between 2026-07-04 and 2026-08-20 the site served a **six-week-old build**. Twenty-two commits to
`marketing/` were sitting in `main`, published to nobody: the whole `/help/which-model` page, the
homepage footer links to it, the landing-page walkthrough, and two separate changes to the model
recommendation.

Nothing alerted on it, because a stale Pages deploy fails silently — the old build keeps serving
200s. The trigger was almost certainly the stored `wrangler` OAuth token expiring on **2026-07-22**;
a token that has lapsed makes every subsequent deploy attempt fail at auth, and if nobody is watching
the terminal it just doesn't happen.

The specific user-visible cost: JobHunt's in-app link *"Which model should I use? — accuracy,
consistency and real costs"* (`ModelRecommendation.helpURL`) pointed at a page that had never been
deployed, so it silently served the landing page instead. The app shipped a link to a 404-in-effect
for six weeks.

**So: after any deploy, verify a page that changed** rather than trusting the command's exit code.

```bash
# Should print the page's own title, not "JobHunt — Local-first job tracker"
curl -s -L https://jobhunt-app.com/help/which-model | grep -oE '<title>[^<]*</title>'
```

To date the currently-live build — useful when you suspect drift — hash the live homepage and match
it against history:

```bash
LIVE=$(curl -s -L https://jobhunt-app.com/ | shasum -a 256 | cut -d' ' -f1)
for c in $(git log --format=%H -- marketing/index.html | head -30); do
  [ "$(git show $c:marketing/index.html | shasum -a 256 | cut -d' ' -f1)" = "$LIVE" ] \
    && git log -1 --format='live build: %h %ad %s' --date=short $c
done
```

## When the site needs a deploy

Any commit touching `marketing/`. Most often:

- **The model recommendation changed** — `marketing/help/which-model.html` and
  `core/LLM/ModelRecommendation.swift` must move together, and the page must then actually go live.
  The app links to the page instead of restating its caveats, so a stale page makes the app's
  recommendation unexplained.
- A release refreshed screenshots, the walkthrough, or the App Store badge.
- FAQ or help content changed.
