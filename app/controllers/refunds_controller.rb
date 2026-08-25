class RefundsController < ApplicationController
  before_action :require_operator!, only: :create

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

  # Demo: re-deliver Stripe's settlement webhook for this refund and show the
  # ledger is unchanged — a live proof of exactly-once. Safe because the
  # settlement path is idempotent (keyed on the refund).
  def replay
    refund = Refund.find(params[:id])
    before = Entry.where(idempotency_key: "refund-settle:#{refund.id}").count
    refund.apply_stripe_succeeded!(stripe_refund_id: refund.stripe_refund_id) if %w[processing settled].include?(refund.status)
    after = Entry.where(idempotency_key: "refund-settle:#{refund.id}").count

    redirect_to refund, notice: "Replayed the settlement webhook. Reversal entries for this refund: #{after} (was #{before}) — booked exactly once."
  end
end
