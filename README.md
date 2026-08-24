<div align="center">

# Refunds & Payouts Ledger

The outbound half of a payments system: a refund state machine, idempotent
reversals, and a double-entry ledger that stays balanced through partial
refunds — built in Rails 8.

[![CI](https://github.com/MohammedAltounsi/rails-refunds-payouts-ledger/actions/workflows/ci.yml/badge.svg)](https://github.com/MohammedAltounsi/rails-refunds-payouts-ledger/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-4.0-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)
![Stripe](https://img.shields.io/badge/Stripe-test%20mode-635BFF?logo=stripe&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-informational)

</div>

This is the companion to
[rails-stripe-wallet-ledger-sandbox](https://github.com/MohammedAltounsi/rails-stripe-wallet-ledger-sandbox),
which builds the inbound half (capture a payment, credit a wallet). This repo
builds the harder direction: giving money back correctly, exactly once, even
when a refund is partial, a webhook is redelivered, or a request is retried.

## What it does

| Area | What happens | Where |
|---|---|---|
| Refund state machine | `requested → processing → settled \| failed`. Every other transition raises `Refund::InvalidTransition`. | `app/models/refund.rb` |
| Over-refund guard | A charge can never be refunded past what it captured, even split across concurrent requests. Enforced in the app (a row lock on the charge) AND in Postgres (a deferred `CONSTRAINT TRIGGER`). | `Refund.request!`, `lib/tasks/db_constraints.rake` |
| Idempotent reversals | Settling a refund posts a balancing ledger entry, keyed on the refund. A redelivered webhook reverses the money once. | `Refund#settle!`, `app/models/ledger.rb` |
| Stripe refunds | Created via the Refund API (test mode). Money is booked only on a signature-verified `refund.updated` webhook, never on the synchronous create response. | `app/models/refund_gateway.rb`, `app/controllers/webhooks/stripe_controller.rb` |
| Webhook inbox | Every Stripe event recorded once (unique `event_id`); a redelivery of an already-processed event is a no-op. | `app/models/stripe_event.rb` |
| Reconciliation | Compares settled refunds against Stripe and reports dropped webhooks, amount mismatches, and orphan reversals. | `app/services/reconciliation_service.rb` |

## How it works

```mermaid
flowchart LR
    Ops[Support tool] -->|issue refund| RC[RefundsController]
    RC --> RS[RefundService]
    RS --> R[Refund.request!\nlocks the charge]
    RS --> G[RefundGateway]
    G <--> S[Stripe]
    S -->|signed webhook| W[Webhooks::StripeController]
    W -->|settle!| L[Ledger]
    L --> DB[(PostgreSQL · balance + over-refund triggers)]
```

1. `Refund.request!` locks the charge, checks the remaining refundable amount,
   and creates the refund row — idempotent on a caller-supplied key.
2. `RefundGateway` calls Stripe. The refund moves to `processing`. A
   synchronous Stripe error fails it immediately; nothing is booked either way.
3. Stripe's `refund.updated` webhook (signature-verified, deduped through the
   inbox) is the only thing that calls `Refund#settle!`, which flips the
   status to `settled` and posts the balancing reversal in one transaction.
4. A redelivered webhook, a retried request, or a double-click all resolve to
   money moving exactly once — the idempotency keys guarantee it, and the
   database enforces it independently of the app.

For the reasoning behind each decision, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Run it

Needs Ruby 4.0+, the [Stripe CLI](https://stripe.com/docs/stripe-cli), and a Stripe test account.

```bash
bundle install
bin/rails db:setup
```

Put your test key in `.env.local` (gitignored):

```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

Run the app and the webhook tunnel in two shells:

```bash
bin/rails server
stripe listen --forward-to localhost:3000/webhooks/stripe --events refund.updated,refund.failed
```

Open <http://localhost:3000>. Issue a refund from `/refunds/new`, watch it
settle when the webhook arrives, and check `/ledger` and `/reconciliation`.

## Tests

```bash
bin/rails test
```

Covers every legal and illegal state transition, the over-refund guard (both
the app-level lock and, on Postgres, the DB trigger), idempotent reversals
under a redelivered webhook, webhook signature verification, and each
reconciliation drift mode. CI runs the suite on Postgres so the deferred
triggers and row locks are actually exercised, plus Brakeman and
bundler-audit on every push.

## Security

- Webhooks are signature-verified before any money moves.
- Content Security Policy, `force_ssl` with HSTS, and a host allowlist.
- rack-attack throttles the refund-issuing endpoint.
- All secrets come from environment variables; the credentials key is never committed.
- Brakeman and bundler-audit gate every push in CI.

## Author

**Mohammed Altounsi**

I build payment systems, e-commerce stores, and the web apps and marketing
that run around them. This repo and its companion wallet ledger are one
working example: money that stays correct under retries, race conditions, and
webhook redelivery.

- LinkedIn: <https://www.linkedin.com/in/mohammed-altounsi/>
- GitHub: [@MohammedAltounsi](https://github.com/MohammedAltounsi)
- Email: mhmdaltounsi@gmail.com

## License

MIT. See [LICENSE](LICENSE).
