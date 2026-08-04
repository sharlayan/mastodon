# frozen_string_literal: true

class FetchRemoteAvatarDecorationsWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 2

  def perform(account_id)
    account = eligible_account(account_id)
    return if account.nil?

    previous_ids = account.avatar_decorations.filter_map { |config| config['id'] }
    user_decorations = fetch_user_decorations(account)
    return if user_decorations.nil?

    if user_decorations.blank?
      clear_decorations(account, previous_ids)
      return
    end

    relevant = fetch_relevant_decorations(account, user_decorations)
    return if relevant.nil?

    existing_by_remote_id = AvatarDecoration
      .where(host: account.domain, remote_id: relevant.map(&:first))
      .index_by(&:remote_id)

    decoration_configs = relevant.filter_map do |remote_id, user_decoration, full_decoration, image_url|
      sync_decoration(account, existing_by_remote_id[remote_id], remote_id, user_decoration, full_decoration, image_url)
    end

    account.update_columns(avatar_decorations: decoration_configs)
    CleanupRemoteAvatarDecorationsWorker.enqueue(previous_ids - decoration_configs.pluck('id'))
  end

  private

  def eligible_account(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil? || account.local?
    return unless Setting.avatar_decorations_enabled && Setting.avatar_decorations_federation_enabled
    return if AvatarDecorationDomainBlock.blocked?(account.domain)

    instance_meta = InstanceMetadata.find_by(domain: account.domain)
    return if instance_meta&.software.present? && !instance_meta.avatar_decorations_compatible?

    account
  end

  def fetch_user_decorations(account)
    user_data = fetch_json("https://#{account.domain}/api/users/show", { username: account.username })
    return if user_data.nil?

    decorations = user_data['avatarDecorations']
    return [] unless decorations.is_a?(Array) && decorations.all?(Hash)

    decorations
  end

  def clear_decorations(account, previous_ids)
    account.update_columns(avatar_decorations: []) if account.avatar_decorations.any?
    CleanupRemoteAvatarDecorationsWorker.enqueue(previous_ids)
  end

  def fetch_relevant_decorations(account, user_decorations)
    all_decorations = fetch_json("https://#{account.domain}/api/get-avatar-decorations", {})
    return unless all_decorations.is_a?(Array)

    decorations_by_id = all_decorations.filter_map do |decoration|
      next unless decoration.is_a?(Hash)

      [decoration['id'].to_s, decoration]
    end.to_h

    user_decorations.first(AvatarDecoration::MAX_REMOTE_DECORATIONS).filter_map do |user_decoration|
      relevant_decoration(user_decoration, decorations_by_id)
    end
  end

  def relevant_decoration(user_decoration, decorations_by_id)
    remote_id = user_decoration['id'].to_s
    return if remote_id.blank?

    full_decoration = decorations_by_id[remote_id]
    image_url = (full_decoration&.dig('url') || user_decoration['url']).to_s.presence
    return unless image_url&.start_with?('https://', 'http://')

    [remote_id, user_decoration, full_decoration, image_url]
  end

  def sync_decoration(account, existing, remote_id, user_decoration, full_decoration, image_url)
    decoration = existing || AvatarDecoration.new(host: account.domain, remote_id:)
    decoration.image_remote_url = image_url.slice(0, 4096)
    decoration.name = (full_decoration&.dig('name') || remote_id).slice(0, 256) if decoration.name.blank?
    decoration.approved = true if decoration.new_record?
    decoration.save! if decoration.changed?
    RedownloadAvatarDecorationWorker.enqueue(decoration.id, account_id: account.id) if decoration.image_file_name.blank?
    AvatarDecoration.normalize_config(decoration.id, user_decoration)
  rescue ActiveRecord::RecordNotUnique
    concurrent = AvatarDecoration.find_by(host: account.domain, remote_id:)
    AvatarDecoration.normalize_config(concurrent.id, user_decoration) if concurrent
  rescue => e
    Rails.logger.warn "FetchRemoteAvatarDecorationsWorker: failed for #{remote_id}@#{account.domain}: #{e.message}"
    nil
  end

  def fetch_json(url, body)
    result = nil

    Request.new(:post, url, body: body.to_json)
      .add_headers('Content-Type' => 'application/json', 'Accept' => 'application/json')
      .perform do |response|
        result = JSON.parse(response.body_with_limit) if response.code == 200
      end

    result
  rescue => e
    Rails.logger.warn "FetchRemoteAvatarDecorationsWorker: HTTP error for #{url}: #{e.message}"
    nil
  end
end
