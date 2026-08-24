# Runbook

What to do when `/reconciliation` or the webhook inbox reports a problem.
This is the operational counterpart to [ARCHITECTURE.md](ARCHITECTURE.md),
written for whoever is on call, not whoever is reading the code.

## "Reconciliation shows drift"

`/reconciliation` (or `bin/rails reconcile`, which exits non-zero; wire it
into a scheduled check) compares settled refunds against Stripe. It reports
one of three things:

### Missing: Stripe refunded, the ledger never recorded it

Cause: a `refund.updated` webhook was never delivered, or was delivered and
failed silently before the inbox existed to catch it.

1. Find the refund in the Stripe Dashboard by its refund ID.
2. Check `StripeEvent` for that event. If it's `failed`, read `.error` and
   fix the root cause, then resend the event from the Stripe Dashboard
   (Developers → Webhooks → the endpoint → find the event → "Resend").
3. If no `StripeEvent` row exists at all, the webhook never reached us
   (endpoint down, wrong URL, or an infra-level 5xx before app code ran).
   Resending from the Stripe Dashboard replays it through the same
   idempotent path, safe because `Refund#settle!` is a no-op if the local
   `Refund` is already `settled`, and books the reversal if it isn't.

### Mismatched: we settled a different amount than Stripe refunded

This should be structurally impossible (`Refund#settle!` books exactly
`amount_cents`, and Stripe was asked to refund exactly that). Treat it as a
data integrity incident, not routine drift:

1. Pull the `Entry` for `refund-settle:<id>` and the Stripe refund object
   side by side.
2. Do NOT re-run reconciliation to "fix" it. It only reports, it never
   writes. Correct the ledger by hand with a new, explicitly-memo'd
   correcting entry (never edit a posting after the fact).

### Orphan: a settled reversal with no matching Stripe refund

The scary one: money left the books with nothing on Stripe's side to back
it. Treat as a security incident first, bug second:

1. Freeze further refund issuance (comment out the route or set
   `Rack::Attack` to block `/refunds` POSTs) until understood.
2. Check `Refund.find(id).stripe_refund_id`. If it's `nil` or doesn't match
   any real Stripe object, something bypassed `RefundGateway` and called
   `Refund#settle!` directly. Audit recent deploys and console access.

## "The over-refund trigger rejected a commit"

This is the system working. It means app code (a bug, or a direct console
`Refund.create!`) tried to commit refunds exceeding what a charge captured.
Read the `ActiveRecord::StatementInvalid` message. It names the charge and
the amounts. Do not disable or loosen the trigger to unblock it; fix the
caller.

## "A refund is stuck in `processing`"

Stripe never delivered a terminal `refund.updated`/`refund.failed`, or
delivered one that failed to process (check `StripeEvent.failed`).

1. Look up the refund on Stripe directly. Its `status` there is ground truth.
2. If Stripe shows `succeeded`/`failed` but we're still `processing`, resend
   the event from the Stripe Dashboard (same idempotent replay as above).
3. If Stripe also shows `pending` after a long time, that's a Stripe-side
   delay (bank-dependent for some refund methods), nothing to fix here.

## Issuing a refund from the command line

`/refunds` is a session-backed HTML form, and it's CSRF-protected like any
other state-changing endpoint in a Rails app with no API auth layer in front
of it. A bare `curl -X POST` gets a 422 (`InvalidAuthenticityToken`), by
design. For a smoke test after a deploy, carry a cookie jar and lift the
token from the form the same way a browser does:

```bash
curl -c cookies.txt -s https://<app>.onrender.com/refunds/new > new_refund.html
TOKEN=$(grep -o 'name="authenticity_token" value="[^"]*"' new_refund.html | cut -d'"' -f4)
curl -b cookies.txt -X POST https://<app>.onrender.com/refunds \
  --data-urlencode "authenticity_token=$TOKEN" \
  --data "charge_id=1&amount_cents=500&idempotency_key=support-ticket-1234"
```

Reuse the same `idempotency_key` on a retry. It returns the existing refund
instead of issuing a second one. A real support tool would put this behind
its own authenticated API, not a scraped form token; this is a demo-scale
substitute for that.
