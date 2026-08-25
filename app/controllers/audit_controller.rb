class AuditController < ApplicationController
  # The audit trail names actors and amounts, so it is not part of the public
  # exhibit the way the ledger is. When auth is configured it is operators only;
  # on the open demo (no ADMIN_PASSWORD) it stays visible over synthetic data.
  before_action :require_operator!

  def index
    @entries = AuditLog.recent.limit(100)
  end
end
