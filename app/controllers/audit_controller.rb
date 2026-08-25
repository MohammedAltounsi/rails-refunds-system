class AuditController < ApplicationController
  def index
    @entries = AuditLog.recent.limit(100)
  end
end
