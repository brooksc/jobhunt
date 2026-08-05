import Foundation

/// Résumé text for demo mode.
///
/// These were stubs of 280 and 175 characters — three sentences of summary prose. That reads fine
/// next to the seeded jobs, whose analyses are generated rather than scored, but it falls apart the
/// moment a prospective user captures a **real** posting: against 15–20 real requirements almost
/// nothing is evidenced, the penalty saturates its cap, and the score floors at 0. Measured before
/// this change: a Duolingo consumer-PM role scored 0, and so did a Reddit *Staff Technical Program
/// Manager* role that is close to a bullseye for this candidate. A prospective user's first instinct
/// is to capture a job they care about, and getting 0 reads as a broken product (TASK-666).
///
/// So these are full-length documents — employment history, scope, metrics and named tools — the
/// things a scorer looks for as evidence.
///
/// **Deliberately not a perfect match.** Every employer here is invented, and the history stops
/// short of a few things a staff-level TPM posting commonly asks for: there is no advertising or
/// monetization domain experience, no direct people management (this is an individual-contributor
/// track), and no mobile release management. Those gaps are real and should show up as gaps — a demo
/// where everything scores 100 demonstrates nothing, and would misrepresent how the scorer behaves.
enum DemoResumes {
    static let full = """
    ALEX MORGAN
    Staff Technical Program Manager · Remote (United States) · alex.morgan@example.com

    SUMMARY
    Staff-level Technical Program Manager with 12 years leading complex, multi-team engineering \
    programs across cloud infrastructure, data platforms, and applied machine learning. Individual \
    contributor track: leads through influence across engineering, product, design, data science and \
    security rather than direct reports. Known for making dependencies and risk visible early, and \
    for written communication that executives actually read.

    EXPERIENCE

    Northwind Cloud — Staff Technical Program Manager, Platform Engineering
    2021–present · Remote
    - Led the multi-year migration of a monolithic service estate to Kubernetes-based microservices \
    across 14 engineering teams; delivered 3 weeks ahead of the committed date with no customer-facing \
    downtime.
    - Own quarterly planning and OKR setting for a 220-engineer organisation: dependency mapping, \
    capacity modelling, and a single tracked plan of record.
    - Built the programme risk process now used org-wide — weekly risk review, explicit owners, and an \
    escalation path that cut average time-to-escalation from 19 days to 4.
    - Report programme health to the VP of Engineering and the executive staff in a weekly written \
    update; present quarterly to the CTO.
    - Drove reliability programme that raised availability from 99.5% to 99.95% over 18 months, \
    including an incident review and postmortem practice adopted by every platform team.

    Meridian Data — Senior Technical Program Manager, Data & ML Platform
    2018–2021 · Seattle, WA
    - Ran the programme that delivered a self-service experimentation platform used by 40+ product \
    teams, taking median A/B test setup from 6 days to under 4 hours.
    - Coordinated the data platform re-architecture (batch to streaming) across data engineering, \
    infrastructure and analytics; managed a 9-month critical path with 30+ tracked dependencies.
    - Partnered with data science on model deployment tooling, cutting time from trained model to \
    production serving from 5 weeks to 6 days.
    - Introduced structured intake and prioritisation for platform requests, replacing an ad-hoc queue \
    of 400+ open tickets.

    Halcyon Systems — Technical Program Manager, Distributed Systems
    2015–2018 · San Francisco, CA
    - Managed delivery of a multi-region replication programme for a distributed storage product, \
    spanning 6 teams and 3 time zones.
    - Coordinated API platform versioning and deprecation across internal and external consumers, \
    including a 12-month migration communicated to 200+ integrators.
    - Established launch readiness reviews and a go/no-go checklist still in use.

    Beacon Analytics — Program Manager, Engineering
    2013–2015 · Austin, TX
    - Ran agile delivery for two product teams; introduced sprint metrics and a public roadmap.
    - Managed vendor relationships and third-party integration schedules.

    SKILLS
    Programme and portfolio management · cross-functional leadership · executive communication · OKRs \
    and quarterly planning · dependency and risk management · capacity modelling · launch readiness \
    and go/no-go · incident review and postmortems · technical writing
    Distributed systems · cloud infrastructure (AWS, GCP) · Kubernetes · microservices · CI/CD · \
    data platforms and pipelines · streaming architectures · applied ML delivery · A/B testing and \
    experimentation · SQL
    Jira · Confluence · Looker · Grafana · Airflow · Git · Figma

    EDUCATION AND CERTIFICATIONS
    B.S. Computer Science, University of Texas at Austin
    PMP · Certified ScrumMaster · AWS Solutions Architect – Associate
    """

    static let condensed = """
    ALEX MORGAN
    Staff Technical Program Manager · Remote (United States) · alex.morgan@example.com

    12 years leading multi-team engineering programmes across cloud infrastructure, data platforms and \
    applied machine learning. Individual contributor; leads through influence.

    Northwind Cloud — Staff TPM, Platform Engineering (2021–present)
    Kubernetes migration across 14 teams, delivered early with no downtime. Quarterly planning and OKRs \
    for 220 engineers. Availability 99.5% to 99.95%.

    Meridian Data — Senior TPM, Data & ML Platform (2018–2021)
    Self-service experimentation platform for 40+ teams. Batch-to-streaming re-architecture, 30+ \
    tracked dependencies.

    Halcyon Systems — TPM, Distributed Systems (2015–2018)
    Multi-region replication across 6 teams and 3 time zones. API deprecation programme for 200+ \
    integrators.

    Beacon Analytics — Program Manager, Engineering (2013–2015)

    Skills: programme management, cross-functional leadership, executive communication, OKRs, risk and \
    dependency management, distributed systems, AWS, GCP, Kubernetes, data pipelines, experimentation, \
    SQL, Jira, Confluence.

    B.S. Computer Science, UT Austin · PMP · CSM · AWS Solutions Architect – Associate
    """
}
