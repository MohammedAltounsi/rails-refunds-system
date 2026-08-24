class AccountsController < ApplicationController
  # The internal ledger view — every account, its derived balance, and the most
  # recent entries. This is the transparency layer: proof that money only moves.
  def index
    @accounts   = Account.order(:name)
    @global_sum = Posting.sum(:amount_cents)
    @entries    = Entry.includes(postings: :account).order(created_at: :desc).limit(15)
  end
end
