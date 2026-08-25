# Who did what. Money movements in a payments system need an actor and a trail,
# so every issued refund and payout records one row here. The actor is the
# Basic-auth user when auth is configured (ADMIN_PASSWORD set), or "demo" on the
# open public showcase.
class AuditLog < ApplicationRecord
  scope :recent, -> { order(created_at: :desc) }

  def self.record!(actor:, action:, subject: nil, detail: nil)
    create!(
      actor:        actor.presence || "demo",
      action:       action,
      subject_type: subject&.class&.name,
      subject_id:   subject&.id,
      detail:       detail
    )
  end
end
