# frozen_string_literal: true

class FetchRemoteAvatarDecorationsWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'pull', retry: 2

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil? || account.local?
    return unless Setting.avatar_decorations_enabled && Setting.avatar_decorations_federation_enabled
    return if AvatarDecorationDomainBlock.blocked?(account.domain)

    instance_meta = InstanceMetadata.find_by(domain: account.domain)
    return if instance_meta&.software.present? && !instance_meta.avatar_decorations_compatible?

    host_url = "https://#{account.domain}"
    previous_ids = account.avatar_decorations.filter_map { |config| config['id'] }

    user_data = fetch_json("#{host_url}/api/users/show", { username: account.username })
    return if user_data.nil?

    user_decorations = user_data['avatarDecorations']
    user_decorations = nil unless user_decorations.is_a?(Array) && user_decorations.all?(Hash)
    if user_decorations.blank?
      account.update_columns(avatar_decorations: []) if account.avatar_decorations.any?
      CleanupRemoteAvatarDecorationsWorker.enqueue(previous_ids)
      return
    end

    all_decorations = fetch_json("#{host_url}/api/get-avatar-decorations", {})
    return if all_decorations.nil? || !all_decorations.is_a?(Array)

    decorations_by_id = all_decorations.index_by { |d| d['id'].to_s }

    relevant = user_decorations.first(AvatarDecoration::MAX_REMOTE_DECORATIONS).filter_map do |ud|
      remote_id = ud['id'].to_s
      next if remote_id.blank?

      full      = decorations_by_id[remote_id]
      image_url = (full&.dig('url') || ud['url']).to_s.presence
      next if image_url.blank?
      next unless image_url.start_with?('https://', 'http://')

      [remote_id, ud, full, image_url]
    end

    existing_by_remote_id = AvatarDecoration
      .where(host: account.domain, remote_id: relevant.map(&:first))
      .index_by(&:remote_id)

    decoration_configs = []

    relevant.each do |remote_id, ud, full, image_url|
      begin
        local_dec = existing_by_remote_id[remote_id] || AvatarDecoration.new(host: account.domain, remote_id: remote_id)
        local_dec.image_remote_url = image_url.slice(0, 4096)
        local_dec.name             = (full&.dig('name') || remote_id).slice(0, 256) if local_dec.name.blank?
        local_dec.approved         = true if local_dec.new_record?
        local_dec.save if local_dec.changed?
        RedownloadAvatarDecorationWorker.enqueue(local_dec.id, account_id: account.id) if local_dec.persisted? && local_dec.image_file_name.blank?
      rescue ActiveRecord::RecordNotUnique
        local_dec = AvatarDecoration.find_by(host: account.domain, remote_id: remote_id)
        next if local_dec.nil?
      rescue => e
        Rails.logger.warn "FetchRemoteAvatarDecorationsWorker: failed for #{remote_id}@#{account.domain}: #{e.message}"
        next
      end

      decoration_configs << {
        'id' => local_dec.id,
        'angle' => ud['angle'].to_f.clamp(-0.5, 0.5),
        'flip_h' => ud['flipH'] == true,
        'offset_x' => ud['offsetX'].to_f.clamp(-0.25, 0.25),
        'offset_y' => ud['offsetY'].to_f.clamp(-0.25, 0.25),
        'scale' => (ud['scale'] || 1.0).to_f.clamp(0.5, 1.5),
        'opacity' => (ud['opacity'] || 1.0).to_f.clamp(0.1, 1.0),
      }
    end

    account.update_columns(avatar_decorations: decoration_configs)
    CleanupRemoteAvatarDecorationsWorker.enqueue(previous_ids - decoration_configs.pluck('id'))
  end

  private

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
