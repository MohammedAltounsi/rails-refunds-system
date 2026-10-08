# Contributing

This is a solo portfolio project. There's no roadmap and I don't expect
outside contributors, but if you find something wrong, a fix is welcome. This
file covers that case, and how to run the test suite if you want to read the
code.

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
Postgres, so those tests run there.

## Money paths get a test

Any change to `Refund`, `Charge`, `Ledger`, `Account`, `Entry`, or the
webhook controller has to ship with a test that would fail without the
change. Read [ARCHITECTURE.md](ARCHITECTURE.md) first: most of what looks
like "extra" code there (the row lock, the deferred trigger, the idempotency
key) is protecting a specific race condition, and a fix that removes one of
those without understanding why it's there will likely reintroduce the bug
it was written to close.

## Pull requests

Keep each one to a single change. Say which invariant the change protects or
fixes. A reviewer needs that to judge it.
