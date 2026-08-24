class Posting < ApplicationRecord
  belongs_to :entry
  belongs_to :account
end
