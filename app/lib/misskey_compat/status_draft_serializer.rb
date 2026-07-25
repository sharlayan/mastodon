# frozen_string_literal: true

class MisskeyCompat::StatusDraftSerializer
  def self.serialize(draft, current_account:, statuses_by_id: nil)
    new(draft, current_account: current_account, statuses_by_id: statuses_by_id).serialize
  end

  def initialize(draft, current_account:, statuses_by_id: nil)
    @draft = draft
    @current_account = current_account
    @statuses_by_id = statuses_by_id
    @data = draft.data || {}
  end

  def serialize
    files = @draft.media_attachments.map { |media| MisskeyCompat::DriveFileSerializer.serialize(media) }

    {
      id: MisskeyCompat::MiId.encode(@draft.id),
      createdAt: @draft.created_at.iso8601,
      text: @data['status'],
      cw: @data['spoiler_text'].presence,
      userId: MisskeyCompat::MiId.encode(@current_account.id),
      user: MisskeyCompat::UserSerializer.serialize(@current_account),
      replyId: encoded_id(@data['in_reply_to_id']),
      renoteId: encoded_id(@data['quoted_status_id']),
      reply: serialized_status(@data['in_reply_to_id']),
      renote: serialized_status(@data['quoted_status_id']),
      visibility: misskey_visibility,
      visibleUserIds: Array(@data['visible_user_ids']).map { |id| MisskeyCompat::MiId.encode(id) },
      fileIds: files.pluck(:id),
      files: files,
      hashtag: nil,
      poll: serialized_poll,
      channelId: nil,
      localOnly: ActiveModel::Type::Boolean.new.cast(@data['local_only']),
      reactionAcceptance: @data['reaction_acceptance'],
      scheduledAt: scheduled_at,
      isActuallyScheduled: false,
    }
  end

  private

  def encoded_id(value)
    MisskeyCompat::MiId.encode(value) if value.present?
  end

  def serialized_status(value)
    status = @statuses_by_id ? @statuses_by_id[value.to_i] : Status.find_by(id: value)
    return if status.nil? || !StatusPolicy.new(@current_account, status).show?

    MisskeyCompat::NoteSerializer.serialize(status, current_account: @current_account)
  end

  def misskey_visibility
    MisskeyCompat::NoteSerializer::VISIBILITY_MAP.fetch(@data['visibility'], 'public')
  end

  def serialized_poll
    poll = @data['poll']
    return nil if poll.blank?

    {
      choices: Array(poll['options']),
      multiple: ActiveModel::Type::Boolean.new.cast(poll['multiple']),
      expiresAt: nil,
      expiredAfter: poll['expires_in'],
    }
  end

  def scheduled_at
    Time.zone.parse(@data['scheduled_at']).to_i * 1000 if @data['scheduled_at'].present?
  end
end
