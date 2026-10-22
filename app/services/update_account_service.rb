# frozen_string_literal: true

class UpdateAccountService < BaseService
  PREVIEW_CARD_REATTRIBUTION_LIMIT = 1_000

  MAX_DECORATIONS = 16

  def call(account, params, raise_error: false)
    drive_images  = []
    was_locked    = account.locked
    update_method = raise_error ? :update! : :update

    params = process_drive_images(account, params, drive_images)
    params = process_avatar_decorations(account, params) if params.key?(:avatar_decorations)
    assign_profile_images(account, params)

    account.send(update_method, params).tap do |ret|
      next unless ret

      authorize_all_follow_requests(account) if was_locked && !account.locked
      check_links(account)
      process_hashtags(account)
      process_attribution_domains(account)
    end
  rescue ActiveRecord::RecordInvalid
    raise if raise_error

    false
  rescue Mastodon::DimensionsValidationError, Mastodon::StreamValidationError => e
    account.errors.add(:avatar, e.message)
    raise ActiveRecord::RecordInvalid, account if raise_error

    false
  ensure
    drive_images.each(&:close!)
  end

  private

  def process_drive_images(account, params, drive_images)
    params = params.dup

    %i(avatar header).each do |attachment|
      id = params.delete(:"#{attachment}_drive_file_id")
      next if id.blank?

      raise ActiveRecord::RecordNotFound unless Setting.drive_enabled && account.local?

      drive_file = account.drive_files.find(id)
      drive_file.with_lock do
        unless Account::Avatar::AVATAR_IMAGE_MIME_TYPES.include?(drive_file.file_content_type)
          account.errors.add(attachment, :invalid)
          raise ActiveRecord::RecordInvalid, account
        end

        params[attachment] = copy_drive_image(account, attachment, drive_file, drive_images)
      end
    end

    params
  end

  def copy_drive_image(account, attachment, drive_file, drive_images)
    image = Tempfile.new(['profile-drive-image', File.extname(drive_file.file_file_name)])
    drive_images << image

    copied = drive_file.file.copy_to_local_file(:original, image.path)

    if copied == false || File.empty?(image.path)
      account.errors.add(attachment, :invalid)
      raise ActiveRecord::RecordInvalid, account
    end

    image.open.binmode
    image
  rescue Errno::ENOENT
    account.errors.add(attachment, :invalid)
    raise ActiveRecord::RecordInvalid, account
  end

  def assign_profile_images(account, params)
    %i(avatar header).each do |attachment|
      next unless params.key?(attachment)

      account.public_send(:"#{attachment}=", params.delete(attachment))
    rescue Mastodon::DimensionsValidationError, Mastodon::StreamValidationError => e
      account.errors.add(attachment, :invalid, message: e.message)
      raise ActiveRecord::RecordInvalid, account
    end
  end

  def process_avatar_decorations(account, params)
    return params unless account.local?
    return params.merge(avatar_decorations: []) unless Setting.avatar_decorations_enabled && !Setting.avatar_decorations_local_only_view

    effective_max = Setting.avatar_decorations_max_count.to_i.clamp(0, MAX_DECORATIONS)
    raw = Array(params[:avatar_decorations]).first(effective_max)
    role = account.user&.role || UserRole.everyone
    available_ids = AvatarDecoration.local.approved.available_to_role(role).pluck(:id).map(&:to_s)

    sanitized = raw.filter_map do |d|
      id = d[:id].to_s
      next unless available_ids.include?(id)

      AvatarDecoration.normalize_config(id.to_i, d)
    end

    params.merge(avatar_decorations: sanitized)
  end

  def authorize_all_follow_requests(account)
    follow_requests = FollowRequest.where(target_account: account)
    follow_requests = follow_requests.preload(:account).reject { |req| req.account.silenced? || req.account.requires_follow_review? }
    AuthorizeFollowWorker.push_bulk(follow_requests, limit: 1_000) do |req|
      [req.account_id, req.target_account_id]
    end
  end

  def check_links(account)
    return unless account.fields.any?(&:requires_verification?)

    VerifyAccountLinksWorker.perform_async(account.id)
  end

  def process_hashtags(account)
    account.tags_as_strings = Extractor.extract_hashtags(account.note)
  end

  def process_attribution_domains(account)
    return unless account.attribute_previously_changed?(:attribution_domains)

    # Go through the most recent cards, and do the rest in a background job
    preview_cards = PreviewCard.where(unverified_author_account: account).reorder(id: :desc).limit(PREVIEW_CARD_REATTRIBUTION_LIMIT).to_a
    should_queue_worker = preview_cards.size == PREVIEW_CARD_REATTRIBUTION_LIMIT

    preview_cards = preview_cards.filter do |preview_card|
      account.can_be_attributed_from?(preview_card.domain)
    rescue Addressable::URI::InvalidURIError
      false
    end

    PreviewCard.where(id: preview_cards.pluck(:id), unverified_author_account: account).update_all(author_account_id: account.id, unverified_author_account_id: nil)

    UpdateLinkCardAttributionWorker.perform_async(account.id) if should_queue_worker
  end
end
