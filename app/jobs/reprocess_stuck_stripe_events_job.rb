# Recovery sweep: re-run any inbox event still stuck in `received` or `failed`
# past a grace window. This recovers a settlement dropped by a crash between
# recording the event and booking the money, the exact "flagged but never
# recovers" gap. Handlers are idempotent, so replaying an event books once.
#
# Scheduled (a cron on Render, or invoked via `rails stripe:reprocess`).
class ReprocessStuckStripeEventsJob < ApplicationJob
  queue_as :default

  def perform(older_than_seconds: 120)
    healed = 0
    StripeEvent.reprocessable(older_than: older_than_seconds.seconds).find_each do |inbox|
      begin
        event = StripeEventProcessor.from_payload(inbox.payload)
        StripeEventProcessor.process(event)
        inbox.mark_processed!
        healed += 1
      rescue => e
        inbox.mark_failed!(e.message)
        Rails.logger.error("reprocess inbox #{inbox.event_id} failed: #{e.message}")
      end
    end
    Rails.logger.info("ReprocessStuckStripeEventsJob: healed #{healed} stuck event(s)") if healed.positive?
    healed
  end
end
