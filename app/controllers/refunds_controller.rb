class RefundsController < ApplicationController
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
    redirect_to refund
  rescue Refund::OverRefund => e
    redirect_to new_refund_path(charge_id: charge.id), alert: e.message
  end
end
