namespace :demo do
  desc "Fire N concurrent refund requests at one charge and prove the guard holds (0 over-refunds)"
  task :concurrency, [ :threads ] => :environment do |_t, args|
    n = (args[:threads] || 20).to_i
    captured = 100_00

    charge = Charge.capture!(stripe_payment_intent_id: "pi_demo_#{SecureRandom.hex(4)}", amount_cents: captured)

    # Each thread tries to refund 10.00. Only 10 of them can fit in 100.00; the
    # rest MUST be rejected by the row-lock (and, on Postgres, the trigger).
    accepted = Concurrent::AtomicFixnum.new(0)
    rejected = Concurrent::AtomicFixnum.new(0)

    threads = Array.new(n) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          begin
            Refund.request!(charge: charge, amount_cents: 10_00, idempotency_key: "demo-#{charge.id}-#{i}")
            accepted.increment
          rescue Refund::OverRefund
            rejected.increment
          end
        end
      end
    end
    threads.each(&:join)

    reserved = charge.reload.refunded_cents

    puts ""
    puts "  CONCURRENCY PROOF: #{n} threads each refunding 10.00 SAR against a 100.00 SAR charge"
    puts "  " + ("─" * 60)
    puts "  Accepted:            #{accepted.value}"
    puts "  Rejected (guard):    #{rejected.value}"
    puts "  Total reserved:      #{'%.2f' % (reserved / 100.0)} SAR"
    puts "  Captured (the cap):  #{'%.2f' % (captured / 100.0)} SAR"
    puts "  " + ("─" * 60)
    if reserved <= captured
      puts "  ✓ NO OVER-REFUND. The charge was never reserved past what it captured."
    else
      puts "  ✗ OVER-REFUND: reserved #{reserved} > captured #{captured}. The guard failed."
      exit 1
    end
    puts ""
  end
end
