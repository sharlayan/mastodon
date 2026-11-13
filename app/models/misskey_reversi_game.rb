# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_reversi_games
#
#  id                       :bigint(8)        not null, primary key
#  account1_ready           :boolean          default(FALSE), not null
#  account2_ready           :boolean          default(FALSE), not null
#  black                    :integer
#  bw                       :string           default("random"), not null
#  can_put_everywhere       :boolean          default(FALSE), not null
#  crc32                    :string
#  ended_at                 :datetime
#  llotheo                  :boolean          default(FALSE), not null
#  logs                     :jsonb            not null
#  looped_board             :boolean          default(FALSE), not null
#  map                      :string           default([]), not null, is an Array
#  no_irregular_rules       :boolean          default(FALSE), not null
#  started_at               :datetime
#  time_limit_for_each_turn :integer          default(90), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account1_id              :bigint(8)        not null
#  account2_id              :bigint(8)        not null
#  surrendered_account_id   :bigint(8)
#  timeout_account_id       :bigint(8)
#  winner_account_id        :bigint(8)
#
class MisskeyReversiGame < ApplicationRecord
  BW_VALUES = %w(random 1 2).freeze
  MAX_MAP_SIZE = 32
  MAP_CELLS = /\A[ \-bw]+\z/
  MAX_TIME_LIMIT = 32_767

  belongs_to :account1, class_name: 'Account'
  belongs_to :account2, class_name: 'Account'

  validates :bw, inclusion: { in: BW_VALUES }
  validates :time_limit_for_each_turn, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_TIME_LIMIT }
  validate :validate_map

  scope :involving, ->(account) { where(account1_id: account.id).or(where(account2_id: account.id)) }
  scope :started, -> { where.not(started_at: nil) }
  scope :not_started, -> { where(started_at: nil) }

  def self.valid_map?(value)
    value.is_a?(Array) && value.size.between?(1, MAX_MAP_SIZE) && value.all? { |row| row.is_a?(String) && row.length.between?(1, MAX_MAP_SIZE) && row.match?(MAP_CELLS) } && value.map(&:length).uniq.size == 1
  end

  def started?
    started_at.present?
  end

  def ended?
    ended_at.present?
  end

  def participant?(account)
    account.present? && [account1_id, account2_id].include?(account.id)
  end

  def slot_of(account)
    return 1 if account&.id == account1_id
    return 2 if account&.id == account2_id

    nil
  end

  def other_account_id(account_id)
    account_id == account1_id ? account2_id : account1_id
  end

  def ready_of?(slot)
    slot == 1 ? account1_ready : account2_ready
  end

  def color_of(account)
    slot = slot_of(account)
    return if slot.nil? || black.nil?

    slot == black
  end

  def account_id_for_color(color)
    color == (black == 1) ? account1_id : account2_id
  end

  def engine
    MisskeyCompat::ReversiEngine.restore(map: map, llotheo: llotheo, can_put_everywhere: can_put_everywhere, looped_board: looped_board, logs: logs)
  end

  private

  def validate_map
    errors.add(:map, :invalid) unless self.class.valid_map?(map)
  end
end
