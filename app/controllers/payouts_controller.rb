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
end
