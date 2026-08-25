# Changelog

This app is continuously deployed from `main`, not released in versioned
cuts, so entries are grouped by date instead of a version number. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) otherwise.

## 2026-08-25

### Added

- Payouts: the outbound-to-payee half. A `Payout` model with the same idempotent
  request (which accrues the liability), strict state machine, convergent webhook
  settlement, and double-entry postings as a refund. Full UI and `payout.paid` /
  `payout.failed` webhook handling.
- Convergent webhook boundary: `apply_stripe_succeeded!` / `apply_stripe_failed!`
  make settlement tolerant of Stripe's out-of-order, at-least-once delivery, so a
  redelivered or early event can no longer 500-loop or leave money unbooked. The
  strict FSM is kept for internal callers.
- Recovery sweep (`ReprocessStuckStripeEventsJob`, `rails stripe:reprocess`):
  re-runs any inbox event stuck unprocessed, healing a crash-dropped settlement.
- Continuous reconciliation: every run is stored (`ReconciliationRun`) so drift
  has a timeline; a Stripe outage reports `unreachable` instead of false orphans;
  settled refunds with a null Stripe id are surfaced as orphans.
- JSON API (`POST`/`GET /api/refunds`) with an `Idempotency-Key` header, an
  OpenAPI spec at `/openapi.yaml`, an audit trail (`/audit`), optional Basic auth
  on money-moving actions (`ADMIN_PASSWORD`), a `/health` database check, a
  replay-webhook idempotency demo, and a `demo:concurrency` over-refund proof.
- Redesigned UI: an ivory editorial ledger aesthetic (Fraunces, Hanken Grotesk,
  JetBrains Mono).

### Fixed

- rack-attack throttle store made explicit and honest (per-process memory, gated
  on the single-worker deploy).
- `bin/rails test` no longer requires the CSS toolchain; `docker-compose.yml`
  gives a local Postgres so the trigger and concurrency tests run locally too.

## 2026-08-24

### Added

- Refund state machine (`requested → processing → settled | failed`) with
  illegal transitions raising `Refund::InvalidTransition`.
- Over-refund guard: an app-level row lock on the charge, backed by a
  Postgres deferred `CONSTRAINT TRIGGER` (`refunds_cannot_exceed_charge`).
- Idempotent ledger reversals keyed on the refund, so a redelivered Stripe
  webhook settles money exactly once.
- Stripe Refund API integration (`RefundGateway`), confirmed only through a
  signature-verified `refund.updated` / `refund.failed` webhook.
- Webhook inbox (`StripeEvent`) for exactly-once event processing, reused
  from the companion wallet ledger project.
- Reconciliation against Stripe's refund list, reporting dropped webhooks,
  amount mismatches, and orphan reversals.
- Double-entry ledger core (`Ledger`, `Account`, `Entry`, `Posting`).
- `RUNBOOK.md`: what to do for each reconciliation drift mode and a stuck
  refund.
- CI on GitHub Actions: full suite on PostgreSQL, plus Brakeman and
  bundler-audit on every push.

### Fixed

- `config/cable.yml` was left on its `rails new` default of a Redis adapter
  in production, which nothing in `render.yaml` provisions. Switched to
  `solid_cable`, matching every other backing store in the app.

### Changed

- Renamed the project from `rails-refunds-payouts-ledger` to
  `rails-refunds-system` (repo, Rails module, Render service, PWA manifest).
