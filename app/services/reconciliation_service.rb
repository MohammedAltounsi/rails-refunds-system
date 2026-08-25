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
    :unbalanced_entries, :global_sum_cents, :stripe_reachable,
    keyword_init: true
  ) do
    # Structurally clean AND matched against Stripe. If Stripe was unreachable
    # we cannot assert either way, so it is neither ok nor drift — see unreachable?.
    def ok?
      stripe_reachable && drift_free? && invariants_hold?
    end

    def unreachable?
      !stripe_reachable
    end

    def drift_free?
      missing.empty? && mismatched.empty? && orphans.empty?
    end

    def invariants_hold?
      unbalanced_entries.empty? && global_sum_cents.zero?
    end
  end

  # stripe/ledger are injectable so the diff logic can be tested without the
  # network. `stripe` is the map of succeeded Stripe refunds; pass
  # stripe_reachable: false to model an outage (then orphan detection is
  # suppressed, because an empty Stripe list would otherwise flag everything).
  def self.run(stripe: :fetch, ledger: settled_refunds_by_stripe_id, stripe_reachable: true)
    if stripe == :fetch
      fetched          = fetch_succeeded_refunds
      stripe           = fetched[:refunds]
      stripe_reachable = fetched[:reachable]
    end

    missing = []; mismatched = []; matched = 0

    stripe.each do |id, info|
      refund = ledger[id]
      if refund.nil?
        missing << { stripe_refund_id: id, amount_cents: info[:amount] }
      elsif posted_amount_for(refund) != info[:amount]
        # Compare the amount actually POSTED to the ledger, not just the
        # refund's requested amount — that is what really moved money.
        mismatched << { stripe_refund_id: id, stripe_cents: info[:amount], ledger_cents: posted_amount_for(refund) }
      else
        matched += 1
      end
    end

    orphans =
      if stripe_reachable
        matched_orphans =
          ledger.reject { |id, _| stripe.key?(id) }.map do |id, refund|
            { stripe_refund_id: id, refund_id: refund.id, ledger_cents: refund.amount_cents }
          end
        # A settled refund with NO stripe_refund_id cannot be matched to Stripe
        # at all — invisible to the loop above. Surface it as an orphan too.
        null_id_orphans =
          Refund.where(status: "settled", stripe_refund_id: nil).map do |refund|
            { stripe_refund_id: nil, refund_id: refund.id, ledger_cents: refund.amount_cents }
          end
        matched_orphans + null_id_orphans
      else
        []
      end

    Result.new(
      stripe_count:       stripe.size,
      matched:            matched,
      missing:            missing,
      mismatched:         mismatched,
      orphans:            orphans,
      unbalanced_entries: Entry.all.reject { |e| e.postings.sum(&:amount_cents).zero? }.map(&:id),
      global_sum_cents:   Posting.sum(:amount_cents),
      stripe_reachable:   stripe_reachable
    )
  end

  def self.settled_refunds_by_stripe_id
    Refund.where(status: "settled").where.not(stripe_refund_id: nil).index_by(&:stripe_refund_id)
  end

  # The amount actually booked to the ledger for this refund's settlement, read
  # from the keyed reversal entry. Falls back to the refund amount if the entry
  # is somehow absent (itself a drift the caller will catch as a mismatch).
  def self.posted_amount_for(refund)
    entry = Entry.find_by(idempotency_key: "refund-settle:#{refund.id}")
    return refund.amount_cents unless entry
    entry.postings.select { |p| p.amount_cents.positive? }.sum(&:amount_cents)
  end

  # Returns { refunds: { stripe_id => { amount: } }, reachable: bool }. On a
  # Stripe outage, reachable is false and refunds is whatever we got (possibly
  # empty), so the caller can report "unreachable" instead of crying orphan.
  def self.fetch_succeeded_refunds
    out = {}
    Stripe::Refund.list(limit: 100).auto_paging_each do |r|
      next unless r.status == "succeeded"
      out[r.id] = { amount: r.amount }
    end
    { refunds: out, reachable: true }
  rescue Stripe::StripeError => e
    Rails.logger.warn("Reconciliation: could not reach Stripe: #{e.message}")
    { refunds: out, reachable: false }
  end
end
