# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_bubble_game_records
#
#  id           :bigint(8)        not null, primary key
#  game_mode    :string           not null
#  game_version :integer          not null
#  is_verified  :boolean          default(FALSE), not null
#  logs         :jsonb            not null
#  score        :integer          not null
#  seed         :string           not null
#  seeded_at    :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint(8)        not null
#
class MisskeyBubbleGameRecord < ApplicationRecord
  RANKING_PERIOD = 7.days
  RANKING_LIMIT = 10
  SEED_MAX_AGE = 5.hours

  belongs_to :account

  scope :ranking, ->(game_mode) { where(game_mode: game_mode, seeded_at: RANKING_PERIOD.ago..).order(score: :desc, id: :asc).limit(RANKING_LIMIT) }
end
