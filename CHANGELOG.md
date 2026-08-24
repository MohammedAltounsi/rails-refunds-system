# Changelog

This app is continuously deployed from `main`, not released in versioned
cuts, so entries are grouped by date instead of a version number. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) otherwise.

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
