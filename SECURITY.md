# Security Policy

## Scope

This is a portfolio project demonstrating payments engineering practices. It
runs entirely against **Stripe test mode**. No real card, no real money, and
no real customer data ever touches it. Treat findings here as you would for
any production payments codebase; the fix matters even though the stakes on
this specific deployment don't.

## Supported versions

There are no version branches. This app is continuously deployed from `main`
to a single live instance. A fix lands as a commit to `main`, not a backport.

## What's already enforced

- Every Stripe webhook is signature-verified (`Stripe::Webhook.construct_event`)
  before any code runs against its payload. A forged or malformed request is
  rejected with no side effects.
- Money is booked only from the verified webhook, never from a synchronous API
  response. See [ARCHITECTURE.md](ARCHITECTURE.md#3-money-is-booked-on-the-webhook-never-on-the-refunds-creation).
- Content Security Policy with per-request script nonces, `force_ssl` with
  HSTS, and a host allowlist (`config/environments/production.rb`).
- rack-attack throttles the refund-issuing endpoint against abuse.
- All secrets (Stripe keys, database URL, Rails master key) come from
  environment variables. `config/master.key` and `.env.local` are gitignored;
  nothing sensitive is committed.
- Brakeman (static analysis) and bundler-audit (known gem CVEs) run on every
  push and every pull request, and a finding fails CI.
- Idempotency is enforced at the database level (unique indexes), not just in
  application code, so a race condition can't double-book money.

## Reporting a vulnerability

Open a [private security advisory](https://github.com/MohammedAltounsi/rails-refunds-system/security/advisories/new)
on this repo, or email **mhmdaltounsi@gmail.com** with a description and
reproduction steps. Since this runs in test mode with no real funds or
personal data at risk, there's no bug bounty, but every report gets read and
a real fix.

Please don't open a public issue for a security finding until it's resolved.
