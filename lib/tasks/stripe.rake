namespace :stripe do
  desc "Recovery sweep: reprocess any inbox event stuck unprocessed (crash-dropped settlements)"
  task :reprocess, [ :older_than_seconds ] => :environment do |_t, args|
    seconds = (args[:older_than_seconds] || 120).to_i
    healed = ReprocessStuckStripeEventsJob.new.perform(older_than_seconds: seconds)
    puts "stripe:reprocess: healed #{healed} stuck event(s) (older than #{seconds}s)."
  end
end
