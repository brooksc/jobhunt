# Security Policy

## Scope

Jobhunt is a local-first Mac app with no cloud backend, no user accounts, and no external data transmission (unless you configure a cloud LLM provider). The attack surface is limited to:

- The local HTTP server on `127.0.0.1` (not accessible outside your machine)
- The Chrome extension communicating with that local server
- SQLite database stored under `~/Library/Application Support/Jobhunt/jobhunt.store` (DMG) or `~/Library/Containers/com.jobhunt-app.jobhunt/Data/Library/Application Support/Jobhunt/jobhunt.store` (MAS)

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Report privately via [GitHub's private vulnerability reporting](https://github.com/brooksc/jobhunt/security/advisories/new) or email the maintainer directly (see profile).

Include a description of the issue, steps to reproduce, and potential impact. You'll receive a response within a few days.
