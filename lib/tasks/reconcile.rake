desc "Reconcile the ledger against Stripe; exits non-zero on any drift (CI-friendly)"
task reconcile: :environment do
  r = ReconciliationService.run

  puts ""
  puts "  REFUNDS & PAYOUTS — LEDGER RECONCILIATION"
  puts "  " + ("─" * 46)
  puts "  Stripe reachable:         #{r.stripe_reachable ? 'yes' : 'NO'}"
  puts "  Stripe refunds (settled): #{r.stripe_count}"
  puts "  Matched to ledger:        #{r.matched}"
  puts "  Every entry balances:     #{r.unbalanced_entries.empty? ? 'yes' : "NO (#{r.unbalanced_entries.size})"}"
  puts "  Ledger sums to zero:      #{r.global_sum_cents.zero? ? 'yes' : "NO (#{r.global_sum_cents})"}"
  puts "  " + ("─" * 46)

  if r.missing.any?
    puts "  ✗ MISSING IN LEDGER (Stripe refunded, we didn't record):"
    r.missing.each { |m| puts "      #{m[:stripe_refund_id]}  #{'%.2f' % (m[:amount_cents]/100.0)} SAR" }
  end
  if r.mismatched.any?
    puts "  ✗ AMOUNT MISMATCH:"
    r.mismatched.each { |m| puts "      #{m[:stripe_refund_id]}  stripe #{m[:stripe_cents]}  ledger #{m[:ledger_cents]}" }
  end
  if r.orphans.any?
    puts "  ✗ ORPHAN REVERSALS (settled in ledger, no matching Stripe refund):"
    r.orphans.each { |o| puts "      refund #{o[:refund_id]}  #{'%.2f' % (o[:ledger_cents]/100.0)} SAR" }
  end

  puts ""
  if r.unreachable?
    puts "  ? UNREACHABLE — could not reach Stripe; ledger invariants #{r.invariants_hold? ? 'hold' : 'FAILED'}."
    puts ""
    exit 2
  elsif r.ok?
    puts "  ✓ CLEAN — ledger and Stripe agree to the halala."
    puts ""
  else
    puts "  ✗ DRIFT DETECTED — see above."
    puts ""
    exit 1
  end
end
