class RefundsController < ApplicationController
  before_action :require_operator!, only: %i[create replay simulate]

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
  # retried request refunds once. Refund.request! is keyed on it.
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

  # Demo: stand in for Stripe's signed webhook so a visitor can drive a
  # `processing` refund to its end state by clicking. It calls the SAME
  # convergent, ordering-tolerant methods a real webhook calls, so the demo is
  # faithful. Off in production (demo_mode? false), where only a
  # signature-verified webhook may settle money. This action then refuses.
  def simulate
    return redirect_to(refunds_path, alert: "Demo actions are disabled here.") unless demo_mode?

    refund = Refund.find(params[:id])
    case params[:outcome]
    when "succeeded"
      refund.apply_stripe_succeeded!(stripe_refund_id: refund.stripe_refund_id || "re_demo_#{refund.id}")
      AuditLog.record!(actor: "demo (simulated webhook)", action: "refund.webhook.succeeded", subject: refund,
                       detail: "settled #{helpers.money(refund.amount_cents)}, reversal booked to the ledger")
      redirect_to refund, notice: "Played Stripe's webhook: settled. The reversal is booked to the ledger, exactly once."
    when "failed"
      refund.apply_stripe_failed!("demo: simulated Stripe failure")
      AuditLog.record!(actor: "demo (simulated webhook)", action: "refund.webhook.failed", subject: refund,
                       detail: "marked failed, no money booked")
      redirect_to refund, notice: "Played Stripe's webhook: failed. No money moved. The ledger is untouched."
    else
      redirect_to refund, alert: "Pick an outcome to simulate."
    end
  end

  # Demo: re-deliver the settlement webhook for an ALREADY-settled refund and
  # show the ledger is unchanged, confirming exactly-once. Restricted to
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
