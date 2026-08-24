## What this changes and why

<!-- One or two sentences. If this touches Refund, Charge, Ledger, Account,
Entry, or the webhook controller, name the invariant it protects or fixes. -->

## Checklist

- [ ] `bin/rails test` passes locally
- [ ] `bin/rubocop` is clean
- [ ] `bin/brakeman -q -w2 --no-pager` reports no new warnings
- [ ] `bin/bundler-audit check` is clean
- [ ] A money-path change (see above) ships with a test that fails without it
