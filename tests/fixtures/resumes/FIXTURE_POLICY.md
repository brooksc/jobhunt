# Test Fixture Policy

## Resume Fixtures

Resume fixtures in this directory must use **synthetic data only** — no real names,
contact information, employment history, or personal details.

### What is allowed
- Fictional names (e.g., "Alex Jordan", "Morgan Lee")
- Placeholder email addresses at `example.com`
- Invented companies and roles that represent realistic resume content
- Enough detail to exercise parsing/extraction code paths

### What is not allowed
- Real names, email addresses, phone numbers, or physical addresses
- Actual employment history or personally identifiable information
- Copies of real resumes, even anonymized ones

### Adding a new fixture
1. Use a fictional persona (first + last name, no real person)
2. Use `@example.com` email addresses
3. Add a footer note: "This is a synthetic resume fixture for automated testing."
4. Name the file `synthetic_<variant>.md` (or `.pdf` for PDF-parse testing)

## History Note

Personal resume files were committed before this policy was established and removed
in a later commit. If this repository has been shared publicly or with third parties,
the git history should be reviewed and rewritten if necessary to expunge those files.
