# Architecture

Why this system is built the way it is. The README covers what it does; this
covers the decisions behind it and what I would change to run it at scale.

## The core model

A `Charge` is a captured payment (owned by this app only as a fact to refund
against; the real capture flow is the companion project). A `Refund`
belongs to a charge, moves through a state machine, and posts a double-entry
`Entry` that reverses the charge's original postings, but only at `settled`.

```
Entry "charge captured pi_123"        Entry "refund 1 for charge pi_123"
  posting  stripe:cash     -4500        posting  revenue:charges  -1500
  posting  revenue:charges +4500        posting  stripe:cash      +1500
                            -----                                  -----
                               0                                      0
```

Every entry sums to zero. A refund's reversal is the mirror image of the
charge it partially undoes.

## Decisions and trade-offs

### 1. The refund state machine only allows real transitions

`Refund::TRANSITIONS` is an explicit allow-list: `requested → processing |
failed`, `processing → settled | failed`, and nothing leaves `settled` or
`failed`. `transition_to!` raises `Refund::InvalidTransition` for anything
else.

- **Why:** a refund's status is a contract with the ledger. `requested →
  settled` (skipping `processing`) would mean booking money for a Stripe call
  that may never have happened. `settled → anything` would mean un-reversing
  a reversal that already happened. An explicit allow-list makes illegal
  states a raised exception, not a silent data-integrity bug.
- **Trade-off:** none. This is a small, fixed set of states; a state machine
  gem would add a dependency for something six lines already do.

### 2. Over-refund is rejected in the app AND by a Postgres trigger

`Refund.request!` locks the charge row (`with_lock`), sums its
`requested + processing + settled` refunds, and raises `Refund::OverRefund`
if a new refund would exceed the captured amount. A deferred `CONSTRAINT
TRIGGER` (`refunds_cannot_exceed_charge`, in `lib/tasks/db_constraints.rake`)
re-checks the same rule at COMMIT, independent of the app.

- **Why the lock:** without it, two concurrent partial-refund requests both
  read "60 SAR left on a 100 SAR charge," both decide their 60 SAR request
  fits, and together refund 120 SAR of a 100 SAR charge. The lock serializes
  requests against the same charge so the second one sees the first's
  reservation.
- **Why reserve on `requested`, not just `settled`:** a `requested` or
  `processing` refund hasn't moved money yet, but it represents an in-flight
  promise to Stripe. Counting only `settled` refunds against the cap would let
  the same race happen one layer up: two refunds could both be issued to
  Stripe before either settles, and both could succeed.
- **Why the trigger too:** the lock only holds if every code path takes it.
  The trigger is the invariant made a property of the database. It would
  catch a future caller that constructs a `Refund` directly, bypassing
  `Refund.request!` entirely.
- **Trade-off:** a global-per-charge lock serializes refund requests against
  one charge. For a single charge's own refunds, rarely more than a handful,
  that is correct and not a throughput concern.

### 3. Money is booked on the webhook, never on the refund's creation

Creating a `Refund` row and calling `RefundGateway.create` moves nothing in
the ledger. `Refund#settle!`, called only from a signature-verified
`refund.updated` webhook, is the sole path that posts the reversal.

- **Why:** Stripe's synchronous response to a refund create call can still
  fail or reverse (insufficient balance on a connected account, a disputed
  card, etc.). Trusting it would book money that isn't final. The webhook is
  the only event that means "Stripe actually gave the money back."
- **How redelivery is handled:** the webhook inbox (`StripeEvent`, see #4)
  dedupes at the event level; `Ledger.post!`'s idempotency key (see #5)
  dedupes at the posting level. Either alone is safe; together they survive a
  crash between recording the event and booking the reversal.

### 4. Webhooks are exactly-once via an inbox

Every Stripe event is written to `stripe_events`, deduped on a unique
`event_id`, processed only if not already `processed`, and marked `failed`
(with a 500 response so Stripe retries) if the handler raises.

- **Why:** Stripe delivers at-least-once. Deduping only on the refund id
  covers money but gives no audit trail for other event types and no way to
  tell a genuinely-new event from a redelivery before processing it.
- **Trade-off:** an extra write per event. Negligible next to the safety.

### 5. Idempotency is enforced at the database, not just checked in code

Both `Refund.request!` (keyed on a caller-supplied idempotency key) and
`Ledger.post!` (keyed on `refund-settle:<id>`) do a fast-path existence check,
then rely on a unique index and `rescue ActiveRecord::RecordNotUnique` for the
race.

- **Why:** a check-then-insert has a gap. Two concurrent requests with the
  same key can both pass the check and both attempt to insert. The unique
  index is the real guard: the database lets exactly one win, the loser
  catches the violation and returns the winner's row.
- **At scale:** unchanged. This is the pattern; it holds under real
  concurrency, and it's the same one project 1 uses for wallet top-ups.

### 6. Balances are derived, never stored

`Account#balance_cents` sums postings on every read. There is no `balance`
column.

- **Why:** a stored balance is a second source of truth that can drift from
  the log. Deriving it means it cannot drift by construction, the same
  reasoning as project 1's wallet.
- **At scale:** add a cached balance projection updated in the same
  transaction as the posting, reconciled periodically against the log. The
  log stays authoritative.

### 7. Reconciliation is a first-class feature

`ReconciliationService` compares settled refunds against Stripe's list of
succeeded refunds and reports three failure modes: a Stripe refund the
ledger never recorded (dropped webhook), a settled amount that disagrees, and
a settled reversal with no matching Stripe refund (money leaving the books
from nowhere). Plus the two structural invariants: every entry balances, and
the global sum is zero.

- **Why:** webhooks get dropped and code has bugs. A ledger that can't be
  checked against the processor that actually moves the money is a ledger you
  have to trust blindly.
- **At scale:** run it continuously over a rolling window instead of a full
  list-and-diff, store each run, and alert on the first non-zero drift.

### 8. Money is integer minor units

Every amount is an integer count of halalas. No floats anywhere in the money
path; the only division by 100 is display formatting.

- **Why:** floating point cannot represent most decimal money values exactly.
  Integer minor units are exact. Standard practice; not worth debating.

### 9. The webhook boundary is convergent, the internal FSM is strict

The strict state machine (#1) is right for our own code, but wrong at the
webhook edge. Stripe delivers events at-least-once and out of order: a
`succeeded` can arrive before we recorded `processing`, or after a crash left
the row `failed`. Raising there would turn Stripe's retries into an infinite
500-loop and never book money Stripe already moved.

So the webhook calls convergent, ordering-tolerant methods
(`apply_stripe_succeeded!`, `apply_stripe_failed!`) instead of the strict
`settle!`/`fail!`. A verified `succeeded` is authoritative: converge to settled
from any non-settled state and book the reversal exactly once (the ledger key
guarantees it). A late `failed` after a settle is ignored, never un-booking
money. The strict FSM stays, and stays tested, for internal callers.

### 10. Settlement stays synchronous; a sweep heals what drops

Settlement is not offloaded to a background job. The only async adapter that
fits a 512 MB single-worker instance is in-memory, which is lost on restart, so
offloading would trade Stripe's durable synchronous retry for a queue that can
silently drop money. Instead the ledger write runs inline (Stripe retries on a
500), and `ReprocessStuckStripeEventsJob` sweeps any inbox event still
unprocessed and re-runs it. Idempotent handlers make the replay safe.

## What I would add next

- A cached balance projection (see #6).
- Alerting on the first non-zero reconciliation run (the runs are already
  stored; this is a notifier on top).
- Real Stripe Connect payouts (this build accrues and disburses against the
  ledger; a live integration would drive `mark_processing!` from a real
  transfer and settle on the real `payout.paid` event, which the webhook
  already handles).
- Reconciliation of payouts against Stripe transfers, mirroring the refund
  reconciliation.

## Testing

- `refund_test`: every legal transition succeeds, every illegal one raises
  and changes nothing, partial refunds are accepted up to the cap, an
  over-refund is rejected even split across two requests, a failed refund
  frees its reserved amount, and a repeated idempotency key returns the same
  refund.
- `refund_concurrency_test` (Postgres only): the DB trigger rejects an
  over-refund committed by app code that skipped the check, and two
  concurrent refund requests for more than remains cannot both succeed.
- `ledger_test` and `idempotency_test`: entries must balance, and a repeated
  key moves money once.
- `webhooks/stripe_controller_test`: a forged signature is rejected, a
  succeeded `refund.updated` settles and reverses once even on redelivery, a
  failed one records the reason and books nothing, and a non-terminal status
  is a no-op.
- `reconciliation_service_test`: each drift mode (missing, mismatch, orphan)
  is detected, and a matching ledger reconciles clean.

CI runs the full suite on Postgres plus Brakeman and bundler-audit on every push.
