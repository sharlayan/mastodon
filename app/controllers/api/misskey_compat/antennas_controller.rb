# frozen_string_literal: true

class Api::MisskeyCompat::AntennasController < Api::MisskeyCompat::BaseController
  include Redisable

  before_action :require_user!
  before_action :set_antenna!, only: [:show, :update, :destroy, :notes]

  def index
    render json: current_account.antennas.order(id: :desc).map { |antenna| serialize(antenna) }
  end

  def show
    render json: serialize(@antenna)
  end

  def create
    antenna = current_account.antennas.new(title: antenna_title)
    apply_params!(antenna)
    antenna.save!
    sync_accounts!(antenna)
    render json: serialize(antenna)
  end

  def update
    @antenna.title = antenna_title if params[:name].present?
    apply_params!(@antenna)
    @antenna.save!
    sync_accounts!(@antenna)
    render json: serialize(@antenna)
  end

  def destroy
    @antenna.destroy!
    head 204
  end

  def notes
    statuses = AntennaFeed.new(@antenna).get(pagination_limit, params[:untilId].presence, params[:sinceId].presence).to_a
    Status.preload_cacheable_associations(statuses)
    mark_read!(@antenna, statuses.first&.id) if params[:untilId].blank?
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  private

  def set_antenna!
    @antenna = current_account.antennas.find(params[:antennaId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such antenna', 'NO_SUCH_ANTENNA', 404)
  end

  def antenna_title
    params[:name].to_s
  end

  def apply_params!(antenna)
    antenna.keywords = flatten_keywords(params[:keywords]) if params.key?(:keywords)
    antenna.exclude_keywords = flatten_keywords(params[:excludeKeywords]) if params.key?(:excludeKeywords)
    antenna.with_media_only = truthy(params[:withFile]) if params.key?(:withFile)
    antenna.any_keywords = antenna.keywords.empty?

    return unless params.key?(:src)

    case params[:src].to_s
    when 'users'
      antenna.any_accounts = false
      antenna.exclude_accounts = []
    when 'users_blacklist'
      antenna.any_accounts = true
      antenna.exclude_accounts = resolve_account_ids(params[:users]).map(&:to_s)
    else
      antenna.any_accounts = true
      antenna.exclude_accounts = []
    end
  end

  def sync_accounts!(antenna)
    return unless params.key?(:src)

    if params[:src].to_s == 'users'
      ids = resolve_account_ids(params[:users])
      antenna.antenna_accounts.includes_only.where.not(account_id: ids).destroy_all
      ids.each do |account_id|
        antenna.antenna_accounts.create_or_find_by!(account_id: account_id) { |aa| aa.exclude = false }
      end
    else
      antenna.antenna_accounts.includes_only.destroy_all
    end
  end

  def resolve_account_ids(users)
    Array(users).filter_map { |acct| resolve_account(acct)&.id }.uniq
  end

  def resolve_account(acct)
    value = acct.to_s.delete_prefix('@')
    return if value.blank?

    username, domain = value.split('@', 2)
    domain = nil if domain.present? && domain.casecmp?(Rails.configuration.x.local_domain).zero?
    Account.find_remote(username, domain)
  end

  def truthy(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def serialize(antenna)
    src, users = derive_src_and_users(antenna)

    {
      id: MisskeyCompat::MiId.encode(antenna.id),
      createdAt: antenna.created_at.iso8601,
      name: antenna.title,
      keywords: nest_keywords(antenna.keywords),
      excludeKeywords: nest_keywords(antenna.exclude_keywords),
      src: src,
      userListId: nil,
      users: users,
      caseSensitive: false,
      localOnly: false,
      excludeBots: false,
      withReplies: false,
      withFile: antenna.with_media_only,
      excludeNotesInSensitiveChannel: false,
      isActive: antenna.available,
      hasUnreadNote: unread?(antenna),
      notify: false,
    }
  end

  def unread?(antenna)
    latest_note_id(antenna) > last_read_id(antenna)
  end

  def latest_note_id(antenna)
    redis.zrevrange(FeedManager.instance.key(:antenna, antenna.id), 0, 0).first.to_i
  end

  def last_read_id(antenna)
    redis.get(read_key(antenna)).to_i
  end

  def mark_read!(antenna, note_id)
    note_id ||= latest_note_id(antenna)
    return if note_id.to_i.zero?

    redis.set(read_key(antenna), note_id) if note_id.to_i > last_read_id(antenna)
  end

  def read_key(antenna)
    "antenna:#{antenna.id}:read"
  end

  def derive_src_and_users(antenna)
    include_ids = antenna.antenna_accounts.includes_only.pluck(:account_id)

    if !antenna.any_accounts? && include_ids.present?
      ['users', accts_for(include_ids)]
    elsif antenna.exclude_accounts.present?
      ['users_blacklist', accts_for(antenna.exclude_accounts.map(&:to_i))]
    else
      ['all', []]
    end
  end

  def accts_for(account_ids)
    Account.where(id: account_ids).map(&:acct)
  end

  def flatten_keywords(value)
    Array(value).flatten.map { |keyword| keyword.to_s.strip }.compact_blank.uniq
  end

  def nest_keywords(keywords)
    list = Array(keywords).flatten.compact_blank
    list.empty? ? [] : [list]
  end
end
