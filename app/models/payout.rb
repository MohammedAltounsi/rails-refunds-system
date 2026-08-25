# A payout's life: requested -> processing -> paid | failed. Money leaves the
# ledger to a payee (a vendor, a marketplace seller) only at `paid`, and only
# via a verified Stripe webhook — the same discipline as a refund, in the other
# direction. Requesting a payout accrues the liability (we now owe it); paying
# it disburses the cash and clears the liability.
class Payout < ApplicationRecord
  class InvalidTransition < StandardError; end

  STATUSES = %w[requested processing paid failed].freeze
  TRANSITIONS = {
    "requested"  => %w[processing failed],
    "processing" => %w[paid failed],
    "paid"       => [],
    "failed"     => []
  }.freeze

  validates :payee, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :amount_cents, numericality: { greater_than: 0 }

  # The only way to create a payout. Idempotent on the caller's key. Accrues the
  # liability in the same transaction the row is created, so the books always
  # show what we owe the moment a payout exists — never a payout with no
  # matching liability.
  def self.request!(payee:, amount_cents:, idempotency_key:)
    return find_by!(idempotency_key: idempotency_key) if exists?(idempotency_key: idempotency_key)

    transaction do
      payout = create!(payee: payee, amount_cents: amount_cents, idempotency_key: idempotency_key)
      payout.send(:post_accrual!)
      payout
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(idempotency_key: idempotency_key)
  end

  def mark_processing!(stripe_payout_id:)
    with_lock do
      transition_to!("processing")
      update!(stripe_payout_id: stripe_payout_id)
    end
  end

  # Strict pay, for the internal happy path (seed, FSM tests): only a
  # `processing` payout may be paid. Disburses the cash and clears the liability.
  def pay!
    with_lock do
      next if status == "paid"
      transition_to!("paid")
      post_disbursement!
    end
  end

  def fail!(reason)
    with_lock do
      transition_to!("failed")
      update!(failure_reason: reason.to_s.first(500))
    end
  end

  # --- Webhook boundary: convergent, ordering-tolerant (see Refund) ----------

  def apply_stripe_paid!(stripe_payout_id: nil)
    with_lock do
      self.stripe_payout_id ||= stripe_payout_id
      next if status == "paid"
      update!(status: "paid", failure_reason: nil)
      post_disbursement!
    end
  end

  def apply_stripe_failed!(reason)
    with_lock do
      next if status == "paid"     # money already disbursed; a stale failed is ignored
      next if status == "failed"
      update!(status: "failed", failure_reason: reason.to_s.first(500))
    end
  end

  private

  # We now owe the payee: liability up, expense recognised. Keyed so a retried
  # request accrues once.
  def post_accrual!
    Ledger.post!(
      "payout #{id} accrued for #{payee}",
      [ [ Ledger.account(Ledger::PAYABLE_ACCOUNT), amount_cents ],
       [ Ledger.account(Ledger::EXPENSE_ACCOUNT), -amount_cents ] ],
      key: "payout-accrue:#{id}"
    )
  end

  # Cash leaves, liability clears. Keyed so a redelivered webhook disburses once.
  def post_disbursement!
    Ledger.post!(
      "payout #{id} paid to #{payee}",
      [ [ Ledger.account(Ledger::CASH_ACCOUNT), amount_cents ],
       [ Ledger.account(Ledger::PAYABLE_ACCOUNT), -amount_cents ] ],
      key: "payout-pay:#{id}"
    )
  end

  def transition_to!(new_status)
    allowed = TRANSITIONS.fetch(status, [])
    raise InvalidTransition, "#{status} -> #{new_status} is not a legal payout transition" unless allowed.include?(new_status)
    update!(status: new_status)
  end
end
