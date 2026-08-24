# HTTP surface

This app is server-rendered HTML, not a JSON API. This documents what each
route actually does and returns, for anyone integrating with it or testing
it directly. For the webhook Stripe calls, see
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

## `POST /webhooks/stripe`

Not for manual or third-party use. Stripe calls this with a signed payload;
see the webhook controller and `ARCHITECTURE.md` for what it does with each
event type.

## `GET /up`

Health check. Returns 200 if the app booted with no exceptions.
