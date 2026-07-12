# frozen_string_literal: true

# == Schema Information
#
# Table name: board_announcements
#
#  id                        :bigint(8)        not null, primary key
#  display                   :string           default("normal"), not null
#  for_existing_users        :boolean          default(FALSE), not null
#  icon                      :string           default("info"), not null
#  need_confirmation_to_read :boolean          default(FALSE), not null
#  published                 :boolean          default(FALSE), not null
#  published_at              :datetime
#  silence                   :boolean          default(FALSE), not null
#  sort_priority             :integer          default(0), not null
#  text                      :text             default(""), not null
#  text_html                 :text             default(""), not null
#  title                     :string           default(""), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint(8)
#

class BoardAnnouncement < ApplicationRecord
  ICONS = %w(info warning error success).freeze
  DISPLAYS = %w(normal banner).freeze

  scope :published, -> { where(published: true) }
  scope :reverse_chronological, -> { order(sort_priority: :desc).order(coalesced_timestamp.desc) }
  scope :banner, -> { where(display: 'banner') }
  scope :for_account, lambda { |account|
    where(for_existing_users: false)
      .or(where(for_existing_users: true).where("#{coalesced_timestamp} <= ?", account.created_at))
  }

  belongs_to :account, optional: true

  has_many :reads, class_name: 'BoardAnnouncementRead', dependent: :destroy, inverse_of: :board_announcement
  has_many :attachments, class_name: 'BoardAnnouncementAttachment', dependent: :destroy, inverse_of: :board_announcement
  has_many :board_announcement_reactions, dependent: :destroy, inverse_of: :board_announcement

  validates :title, presence: true, length: { maximum: 256 }
  validates :text, presence: true, length: { maximum: 65_535 }
  validates :icon, inclusion: { in: ICONS }
  validates :display, inclusion: { in: DISPLAYS }

  before_save :render_text_html
  before_save :set_published_at

  class << self
    def coalesced_timestamp
      Arel.sql('COALESCE(board_announcements.published_at, board_announcements.created_at)')
    end

    def reaction_groups_map(announcement_ids, account = nil)
      records = BoardAnnouncementReaction
        .where(board_announcement_id: announcement_ids)
        .group(:board_announcement_id, :name, :custom_emoji_id)
        .order(Arel.sql('MIN(board_announcement_reactions.created_at)').asc)
        .select(
          [:board_announcement_id, :name, :custom_emoji_id, 'COUNT(*) as count'].tap do |values|
            values << value_for_reaction_me_column(account)
          end
        ).to_a

      ActiveRecord::Associations::Preloader.new(records: records, associations: :custom_emoji).call
      records.group_by(&:board_announcement_id)
    end

    private

    def value_for_reaction_me_column(account)
      return 'FALSE AS me' if account.nil?

      <<~SQL.squish
        EXISTS(
          SELECT 1
          FROM board_announcement_reactions inner_reactions
          WHERE inner_reactions.account_id = #{account.id.to_i}
            AND inner_reactions.board_announcement_id = board_announcement_reactions.board_announcement_id
            AND inner_reactions.name = board_announcement_reactions.name
        ) AS me
      SQL
    end
  end

  def to_log_human_identifier
    title
  end

  def publish!
    update!(published: true, published_at: published_at || Time.now.utc)
  end

  def unpublish!
    update!(published: false)
  end

  def read?(account)
    return false if account.nil?

    reads.exists?(account_id: account.id)
  end

  def emojis
    @emojis ||= CustomEmoji.from_text(text)
  end

  def reactions(account = nil)
    grouped_ordered_board_announcement_reactions.select(
      [:name, :custom_emoji_id, 'COUNT(*) as count'].tap do |values|
        values << value_for_reaction_me_column(account)
      end
    ).to_a.tap do |records|
      ActiveRecord::Associations::Preloader.new(records: records, associations: :custom_emoji).call
    end
  end

  private

  def grouped_ordered_board_announcement_reactions
    board_announcement_reactions
      .group(:board_announcement_id, :name, :custom_emoji_id)
      .order(
        Arel.sql('MIN(created_at)').asc
      )
  end

  def value_for_reaction_me_column(account)
    if account.nil?
      'FALSE AS me'
    else
      <<~SQL.squish
        EXISTS(
          SELECT 1
          FROM board_announcement_reactions inner_reactions
          WHERE inner_reactions.account_id = #{account.id}
            AND inner_reactions.board_announcement_id = board_announcement_reactions.board_announcement_id
            AND inner_reactions.name = board_announcement_reactions.name
        ) AS me
      SQL
    end
  end

  def render_text_html
    return unless title_changed? || text_changed?

    self.text_html = BoardAnnouncementFormatter.new(text).to_html
  end

  def set_published_at
    self.published_at = Time.now.utc if published? && published_at.blank?
  end
end
