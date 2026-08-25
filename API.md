# HTTP surface

The operator screens are server-rendered HTML; there is also a small JSON API
(`/api/refunds`) for programmatic use. This documents what each route does and
returns. For the webhook Stripe calls, see
[ARCHITECTURE.md](ARCHITECTURE.md#4-webhooks-are-exactly-once-via-an-inbox).

## `GET /refunds`

Lists the 50 most recent refunds with their charge, amount, and status.

## `GET /refunds/new?charge_id=<id>`

The refund-issuing form. `charge_id` pre-selects that charge.

## `POST /refunds`

Issues a refund. This is what a support tool would call.

| Param | Required | Notes |
|---|---|---|
| `charge_id` | yes | The `Charge` to refund against |
| `amount_cents` | yes | Integer halalas. Rejected if it would exceed the charge's remaining refundable amount |
| `idempotency_key` | no | A stable key from your own retry logic. Submitting the same key twice returns the existing refund instead of issuing a second one. Generated automatically if omitted |

Redirects to `GET /refunds/:id` on success, or back to the form with an
`OverRefund` message if the amount is too large.

This route is session-backed and CSRF-protected like any other Rails form,
so a bare `curl -X POST` gets a 422. See
[RUNBOOK.md](RUNBOOK.md#issuing-a-refund-from-the-command-line) for how to
call it without a browser.

## `GET /refunds/:id`

A single refund's status, amount, Stripe refund ID, and failure reason if it
has one.

## `GET /charges`

Lists the 50 most recent charges with captured, refunded, and refundable
totals.

## `GET /charges/:id`

A single charge plus every refund issued against it.

## `GET /ledger`

Every account's derived balance, the running global sum (always zero if the
ledger is healthy), and the 15 most recent entries.

## `GET /reconciliation`

Compares settled refunds against Stripe and reports drift. Cached for 5
minutes; see [RUNBOOK.md](RUNBOOK.md) for what to do with what it reports.

## Payouts

`GET /payouts`, `GET /payouts/new`, `POST /payouts`, `GET /payouts/:id` mirror
the refund routes for money going out to a payee. `POST /payouts` takes `payee`,
`amount_cents`, and an optional `idempotency_key`. Requesting a payout accrues
the liability; the cash is disbursed only on a verified `payout.paid` webhook.

## JSON API

### `POST /api/refunds`

Issues a refund and returns it as JSON. Honors an `Idempotency-Key` request
header the same way Stripe's own API does: the same key twice issues the refund
once and returns the same resource.

```bash
curl -X POST https://rails-refunds-system.onrender.com/api/refunds \
  -H "Idempotency-Key: your-stable-key" \
  -d "charge_id=1&amount_cents=1500"
```

Returns `201` with the refund, `422 {"error":"over_refund"}` if it would exceed
the charge's remaining refundable amount, or `404` if the charge is unknown.
The full spec is at [`/openapi.yaml`](public/openapi.yaml).

### `GET /api/refunds/:id`

The refund as JSON, or `404`.

## `GET /audit`

The audit trail: every issued refund and payout with its actor and action.

## `POST /webhooks/stripe`

Not for manual or third-party use. Stripe calls this with a signed payload;
see the webhook controller and `ARCHITECTURE.md` for what it does with each
event type (`refund.updated`, `refund.failed`, `payout.paid`, `payout.failed`).

## `GET /up` and `GET /health`

`/up` is Render's process health check (200 if the app booted). `/health` is a
richer JSON check that the app can actually reach its database.
