# A richer health check than Render's /up (which only proves the process is up).
# This one proves the app can reach its database, the thing that actually
# matters for a payments service. JSON, no browser gate, so monitors can poll it.
class HealthController < ActionController::Base
  def show
    db_up =
      begin
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue StandardError
        false
      end

    render json: {
      status:   db_up ? "ok" : "degraded",
      database: db_up ? "up" : "down",
      time:     Time.current.utc.iso8601
    }, status: (db_up ? :ok : :service_unavailable)
  end
end
