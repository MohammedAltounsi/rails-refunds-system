# Reconciliation: "does our ledger agree with Stripe, to the halala?"
#
# Three ways money can silently go wrong, all caught here:
#
#   missing     Stripe refunded the card but our ledger never recorded it
#               (a dropped webhook). We owe our books a reversal.
#   mismatched  We settled a different amount than Stripe actually refunded.
#   orphan      Our ledger settled a refund with NO matching succeeded
#               refund on Stripe. (the scary one — money leaving from nowhere.)
#
# Plus two internal invariants that must always hold:
#   - every entry balances (its postings sum to zero)
#   - the whole ledger sums to zero (money is only moved, never created)
module ReconciliationService
  Result = Struct.new(
    :stripe_count, :matched, :missing, :mismatched, :orphans,
    :unbalanced_entries, :global_sum_cents,
    keyword_init: true
  ) do
    def ok?
      missing.empty? && mismatched.empty? && orphans.empty? &&
        unbalanced_entries.empty? && global_sum_cents.zero?
    end
  end

  # stripe/ledger are injectable so the diff logic can be tested without the
  # network; in production both default to the real fetchers.
  def self.run(stripe: fetch_succeeded_refunds, ledger: settled_refunds_by_stripe_id)
    missing = []; mismatched = []; matched = 0

    stripe.each do |id, info|
      refund = ledger[id]
      if refund.nil?
        missing << { stripe_refund_id: id, amount_cents: info[:amount] }
      elsif refund.amount_cents != info[:amount]
        mismatched << { stripe_refund_id: id, stripe_cents: info[:amount], ledger_cents: refund.amount_cents }
      else
        matched += 1
      end
    end

    orphans = ledger.reject { |id, _| stripe.key?(id) }.map do |id, refund|
      { stripe_refund_id: id, refund_id: refund.id, ledger_cents: refund.amount_cents }
    end

    Result.new(
      stripe_count:       stripe.size,
      matched:            matched,
      missing:            missing,
      mismatched:         mismatched,
      orphans:            orphans,
      unbalanced_entries: Entry.all.reject { |e| e.postings.sum(&:amount_cents).zero? }.map(&:id),
      global_sum_cents:   Posting.sum(:amount_cents)
    )
  end

  def self.settled_refunds_by_stripe_id
    Refund.where(status: "settled").where.not(stripe_refund_id: nil).index_by(&:stripe_refund_id)
  end

  def self.fetch_succeeded_refunds
    out = {}
    Stripe::Refund.list(limit: 100).auto_paging_each do |r|
      next unless r.status == "succeeded"
      out[r.id] = { amount: r.amount }
    end
    out
  rescue Stripe::StripeError => e
    Rails.logger.warn("Reconciliation: could not reach Stripe: #{e.message}")
    out
  end
end
