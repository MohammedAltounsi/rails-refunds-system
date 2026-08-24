require "test_helper"

class LedgerTest < ActiveSupport::TestCase
  setup do
    @cash    = Account.create!(name: "cash:test")
    @revenue = Account.create!(name: "revenue:test")
  end

  test "a balanced entry posts and moves money" do
    Ledger.post!("capture 50 SAR", [ [ @cash, -5000 ], [ @revenue, +5000 ] ])

    assert_equal(-5000, @cash.balance_cents)
    assert_equal(+5000, @revenue.balance_cents)
  end

  test "an unbalanced entry is refused and nothing is written" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Ledger.post!("bad", [ [ @cash, -5000 ], [ @revenue, +4000 ] ]) # 1000 would vanish
    end

    assert_equal 0, Posting.count
    assert_equal 0, @revenue.balance_cents
  end

  test "the golden invariant: every posting in the whole ledger sums to zero" do
    Ledger.post!("capture 50 SAR", [ [ @cash, -5000 ], [ @revenue, +5000 ] ])
    Ledger.post!("refund 12 SAR",  [ [ @revenue, -1200 ], [ @cash, +1200 ] ])

    assert_equal 0, Posting.sum(:amount_cents)
  end
end
