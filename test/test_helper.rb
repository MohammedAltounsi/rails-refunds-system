ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run serially, on purpose. These tests assert GLOBAL ledger invariants
    # (Posting.sum == 0, an account's derived balance) against one shared
    # database. Thread parallelization would let concurrent tests see each
    # other's postings and collide on SQLite's single writer. The suite is fast;
    # correctness of the money assertions matters more than a second saved.
    parallelize(workers: 1)

    # No fixtures — every test builds the state it needs.
  end
end
