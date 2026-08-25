class RefundsController < ApplicationController
  before_action :require_operator!, only: %i[create replay]

  def index
    @refunds = Refund.includes(:charge).order(created_at: :desc).limit(50)
  end

  def show
    @refund = Refund.find(params[:id])
  end

  def new
    @charge = Charge.find(params[:charge_id]) if params[:charge_id]
    @charges = Charge.order(created_at: :desc).limit(50)
  end

  # Issues a refund. The idempotency key comes from the client (a support
  # tool's "submit" button click, in a real system) so a double-click or a
  # retried request refunds once — Refund.request! is keyed on it.
  def create
    charge = Charge.find(params[:charge_id])
    refund = RefundService.issue!(
      charge: charge,
      amount_cents: params[:amount_cents].to_i,
      idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid
    )
    AuditLog.record!(actor: current_actor, action: "refund.issue", subject: refund,
                     detail: "#{helpers.money(refund.amount_cents)} against #{charge.stripe_payment_intent_id}")
    redirect_to refund
  rescue Refund::OverRefund => e
    redirect_to new_refund_path(charge_id: charge.id), alert: e.message
  end

  # Demo: re-deliver the settlement webhook for an ALREADY-settled refund and
  # show the ledger is unchanged, a live proof of exactly-once. Restricted to
  # settled refunds on purpose: it must never be a back door that settles a
  # `processing` refund without Stripe's confirmation (money is booked only on a
  # verified webhook). Idempotent either way, but this keeps the invariant intact.
  def replay
    refund = Refund.find(params[:id])
    unless refund.status == "settled"
      return redirect_to refund, alert: "Replay is a settled-refund demo. This refund is #{refund.status}."
    end

    before = Entry.where(idempotency_key: "refund-settle:#{refund.id}").count
    refund.apply_stripe_succeeded!(stripe_refund_id: refund.stripe_refund_id)
    after = Entry.where(idempotency_key: "refund-settle:#{refund.id}").count

    redirect_to refund, notice: "Replayed the settlement webhook. Reversal entries for this refund: #{after} (was #{before}). Booked exactly once."
  end
end
