require "test_helper"

class IdempotencyTest < ActiveSupport::TestCase
  setup do
    @cash    = Account.create!(name: "cash")
    @revenue = Account.create!(name: "revenue")
  end

  test "same idempotency key moves money only once" do
    key = "refund-abc-123"
    e1 = Ledger.post!("refund 50 SAR", [ [ @revenue, -5000 ], [ @cash, 5000 ] ], key: key)
    e2 = Ledger.post!("refund 50 SAR", [ [ @revenue, -5000 ], [ @cash, 5000 ] ], key: key) # retry

    assert_equal e1.id, e2.id
    assert_equal 1, Entry.where(idempotency_key: key).count
    assert_equal(-5000, @revenue.balance_cents) # reversed once, not twice
  end

  test "different keys post separately" do
    Ledger.post!("t1", [ [ @revenue, -5000 ], [ @cash, 5000 ] ], key: "k1")
    Ledger.post!("t2", [ [ @revenue, -3000 ], [ @cash, 3000 ] ], key: "k2")
    assert_equal(-8000, @revenue.balance_cents)
  end

  test "no key still works — each call is its own entry" do
    Ledger.post!("t", [ [ @revenue, -1000 ], [ @cash, 1000 ] ])
    Ledger.post!("t", [ [ @revenue, -1000 ], [ @cash, 1000 ] ])
    assert_equal(-2000, @revenue.balance_cents)
  end

  test "the DB unique index is the real guard against duplicates" do
    Entry.create!(memo: "first", idempotency_key: "dup")
    assert_raises(ActiveRecord::RecordNotUnique) do
      # bypass Rails validations to prove the DATABASE itself refuses the dupe
      Entry.new(memo: "second", idempotency_key: "dup").save!(validate: false)
    end
  end
end
