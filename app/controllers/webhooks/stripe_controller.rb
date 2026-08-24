module Webhooks
  class StripeController < ApplicationController
    # Stripe posts here from its own servers — no browser, no CSRF token to check.
    skip_forgery_protection

    def create
      payload    = request.body.read
      sig_header = request.headers["Stripe-Signature"]
      secret     = ENV["STRIPE_WEBHOOK_SECRET"]

      # 1. Prove the event really came from Stripe. Without this, anyone who
      #    finds this URL could POST a fake "refund succeeded" and make the
      #    ledger think money left that never did.
      event = Stripe::Webhook.construct_event(payload, sig_header, secret)

      # 2. Inbox: record the event once. Stripe delivers at-least-once, so a
      #    redelivery we've already processed returns 200 immediately and
      #    touches no money.
      inbox = StripeEvent.record(event, payload)
      return head :ok if inbox.processed?

      # 3. Money is real ONLY on a refund that Stripe reports as settled. The
      #    handlers are themselves idempotent (keyed on the refund id), so
      #    even a retry after a mid-processing crash reverses money once.
      handle(event)
      inbox.mark_processed!

      head :ok
    rescue Stripe::SignatureVerificationError, JSON::ParserError
      head :bad_request   # forged or malformed — refuse it, move no money
    rescue => e
      # Processing failed after the event was recorded. Mark it and return 500
      # so Stripe redelivers; on that retry the inbox row is unprocessed, so
      # we run again, and the idempotent ledger keeps money exactly-once.
      inbox&.mark_failed!(e.message)
      Rails.logger.error("stripe webhook #{event&.id} (#{event&.type}) failed: #{e.message}")
      head :internal_server_error
    end

    private

    def handle(event)
      case event.type
      when "refund.updated" then handle_refund_updated(event.data.object)
      when "refund.failed"  then handle_refund_failed(event.data.object)
      end
    end

    # A refund we created has a status change. We only act on the two
    # terminal-adjacent states: succeeded books the reversal, failed records
    # why. Anything else (e.g. "pending") is a no-op — nothing to settle yet.
    def handle_refund_updated(stripe_refund)
      refund = find_refund(stripe_refund)
      return unless refund

      case stripe_refund.status
      when "succeeded" then refund.settle! unless refund.status == "settled"
      when "failed"    then refund.fail!("stripe: #{stripe_refund.failure_reason}") if refund.status != "failed"
      end
    end

    def handle_refund_failed(stripe_refund)
      refund = find_refund(stripe_refund)
      return unless refund
      refund.fail!("stripe: #{stripe_refund.failure_reason}") if refund.status != "failed"
    end

    def find_refund(stripe_refund)
      Refund.find_by(id: stripe_refund.metadata["refund_id"]) ||
        Refund.find_by(stripe_refund_id: stripe_refund.id)
    end
  end
end
