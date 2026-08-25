module Api
  # A JSON API for issuing refunds, honoring an `Idempotency-Key` request header
  # exactly the way Stripe's own API does: the same key POSTed twice issues the
  # refund once and returns the same resource. Inherits ActionController::API so
  # non-browser clients aren't gated by the modern-browser check.
  class RefundsController < ActionController::API
    include OperatorAuthentication

    # Same access control as the HTML refund form: locked behind Basic auth when
    # ADMIN_PASSWORD is set, open on the public demo. Without this, setting the
    # password would lock the UI but leave the API an open money-moving endpoint.
    before_action :require_operator!, only: :create

    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not_found" }, status: :not_found
    end

    def create
      charge = Charge.find(params[:charge_id])
      key    = request.headers["Idempotency-Key"].presence ||
               params[:idempotency_key].presence || SecureRandom.uuid

      refund = RefundService.issue!(charge: charge, amount_cents: params[:amount_cents].to_i, idempotency_key: key)
      AuditLog.record!(actor: "api", action: "refund.issue", subject: refund,
                       detail: "#{refund.amount_cents} halalas against #{charge.stripe_payment_intent_id}")
      render json: serialize(refund), status: :created
    rescue Refund::OverRefund => e
      render json: { error: "over_refund", message: e.message }, status: :unprocessable_entity
    end

    def show
      render json: serialize(Refund.find(params[:id]))
    end

    private

    def serialize(refund)
      {
        id:               refund.id,
        status:           refund.status,
        amount_cents:     refund.amount_cents,
        currency:         refund.charge.currency,
        charge:           refund.charge.stripe_payment_intent_id,
        stripe_refund_id: refund.stripe_refund_id,
        idempotency_key:  refund.idempotency_key,
        created_at:       refund.created_at.utc.iso8601
      }
    end
  end
end
