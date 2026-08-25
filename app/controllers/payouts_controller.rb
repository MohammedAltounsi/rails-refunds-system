class PayoutsController < ApplicationController
  before_action :require_operator!, only: :create

  def index
    @payouts = Payout.order(created_at: :desc).limit(50)
  end

  def show
    @payout = Payout.find(params[:id])
  end

  def new
  end

  # Issues a payout. The idempotency key comes from the client so a double-click
  # or a retried request pays out once — Payout.request! is keyed on it.
  def create
    payout = PayoutService.issue!(
      payee: params[:payee].to_s.strip,
      amount_cents: params[:amount_cents].to_i,
      idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid
    )
    AuditLog.record!(actor: current_actor, action: "payout.issue", subject: payout,
                     detail: "#{helpers.money(payout.amount_cents)} to #{payout.payee}")
    redirect_to payout
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_payout_path, alert: e.message
  end

  # Demo: play Stripe's `payout.paid` / `payout.failed` webhook so a visitor can
  # drive a `processing` payout to its end state by clicking. Calls the same
  # convergent methods a real webhook calls. Off in production (demo_mode? false).
  def simulate
    return redirect_to(payouts_path, alert: "Demo actions are disabled here.") unless demo_mode?

    payout = Payout.find(params[:id])
    case params[:outcome]
    when "paid"
      payout.apply_stripe_paid!(stripe_payout_id: payout.stripe_payout_id || "po_demo_#{payout.id}")
      AuditLog.record!(actor: "demo (simulated webhook)", action: "payout.webhook.paid", subject: payout,
                       detail: "paid #{helpers.money(payout.amount_cents)} to #{payout.payee} — disbursement booked")
      redirect_to payout, notice: "Played Stripe's webhook: paid. The disbursement is on the ledger."
    when "failed"
      payout.apply_stripe_failed!("demo: simulated Stripe failure")
      AuditLog.record!(actor: "demo (simulated webhook)", action: "payout.webhook.failed", subject: payout,
                       detail: "marked failed — no cash disbursed; the accrued liability stands")
      redirect_to payout, notice: "Played Stripe's webhook: failed. No cash was disbursed; the accrued liability stays on the books."
    else
      redirect_to payout, alert: "Pick an outcome to simulate."
    end
  end
end
