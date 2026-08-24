# Contributing

This is a solo portfolio project, not a community-maintained gem, so there's
no roadmap and no expectation of external contributors. That said, if
something here is genuinely wrong, a fix is welcome. This document is mostly
for that case, and for anyone (an interviewer included) who wants to run the
suite and poke at the code.

## Setup

```bash
bundle install
bin/rails db:setup
```

Put Stripe test credentials in `.env.local` (gitignored):

```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

## Running the checks

Everything here also runs in CI on every push; run it locally before opening
a pull request so nothing shows up red.

```bash
bin/rails test
bin/rubocop
bin/brakeman -q -w2 --no-pager
bin/bundler-audit check
```

The test suite runs on SQLite locally and skips two tests that only make
sense on PostgreSQL (`refund_concurrency_test.rb`): the over-refund database
trigger and the two-concurrent-requests race. CI runs the full suite on
Postgres, so those are actually exercised there, not just assumed correct.

## The one real rule: money paths get a test

Any change to `Refund`, `Charge`, `Ledger`, `Account`, `Entry`, or the
webhook controller has to ship with a test that would fail without the
change. Read [ARCHITECTURE.md](ARCHITECTURE.md) first: most of what looks
like "extra" code there (the row lock, the deferred trigger, the idempotency
key) is protecting a specific race condition, and a fix that removes one of
those without understanding why it's there will likely reintroduce the bug
it was written to close.

## Pull requests

Keep them scoped to one change. Describe what invariant the change protects
or fixes, not just what the diff does; that's the part a reviewer actually
needs to evaluate it.
