# frozen_string_literal: true

class Api::MisskeyCompat::AccountsController < Api::MisskeyCompat::BaseController
  requires_write_scope :update_memo, :report_abuse
  requires_misskey_permission 'read:account', :followers, :following, :search, :search_by_username_and_host
  requires_misskey_permission 'write:account', :update_memo
  requires_misskey_permission 'write:report-abuse', :report_abuse

  before_action :require_user!, only: [:followers, :following, :search, :search_by_username_and_host, :update_memo, :report_abuse]

  def index
    scope = apply_user_origin(Account.discoverable.without_suspended)
    scope = scope.where(domain: normalized_hostname) if normalized_hostname
    accounts = apply_user_sort(scope).limit(pagination_limit).offset(params[:offset].to_i).to_a
    relationships = account_relationships(accounts)

    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: current_account, relationships: relationships) }
  end

  def notes
    account = Account.find(params[:userId])
    filter = AccountStatusesFilter.new(account, current_account, statuses_filter_params)
    statuses = filter.results.to_a_paginated_by_id(pagination_limit, max_id: params[:untilId].presence, since_id: params[:sinceId].presence).to_a
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def search
    query = params[:query].to_s.strip
    return render json: [] if query.blank?
    return if rate_limited?(:misskey_compat_api)

    accounts = AccountSearchService.new.call(
      query,
      current_account,
      limit: pagination_limit,
      offset: params[:offset].to_i,
      resolve: false
    )

    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: ActiveModel::Type::Boolean.new.cast(params[:detail])) }
  end

  def search_by_username_and_host
    username = params[:username].to_s.strip.delete_prefix('@')
    host = params[:host].to_s.strip.delete_prefix('@').presence
    return render json: [] if username.blank? && host.blank?

    scope = Account.without_suspended
    scope = scope.where('lower(accounts.username) LIKE ?', "#{ActiveRecord::Base.sanitize_sql_like(username.downcase)}%") if username.present?
    scope = apply_host_filter(scope, host) if params.key?(:host)
    accounts = scope.limit(pagination_limit).to_a
    relationships = account_relationships(accounts)

    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: ActiveModel::Type::Boolean.new.cast(params[:detail]), viewer: current_account, relationships: relationships) }
  end

  def update_memo
    target = Account.find(params[:userId])
    memo = params[:memo].to_s

    if memo.blank?
      current_account.account_notes.find_by(target_account: target)&.destroy
    else
      note = current_account.account_notes.find_or_initialize_by(target_account: target)
      note.comment = memo
      note.save! if note.changed?
    end

    head 204
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def followers
    target = Account.find(params[:userId])
    return render json: [] if collections_hidden?(target, target.hides_followers?)

    follows = paginate_follows(Follow.where(target_account_id: target.id).includes(:account).order(id: :desc))
    render json: follows.map { |follow|
      { id: MisskeyCompat::MiId.encode(follow.id), createdAt: follow.created_at.iso8601, followerId: MisskeyCompat::MiId.encode(follow.account_id), follower: MisskeyCompat::UserSerializer.serialize(follow.account) }
    }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def following
    target = Account.find(params[:userId])
    return render json: [] if collections_hidden?(target, target.hides_following?)

    follows = paginate_follows(Follow.where(account_id: target.id).includes(:target_account).order(id: :desc))
    render json: follows.map { |follow|
      { id: MisskeyCompat::MiId.encode(follow.id), createdAt: follow.created_at.iso8601, followeeId: MisskeyCompat::MiId.encode(follow.target_account_id), followee: MisskeyCompat::UserSerializer.serialize(follow.target_account) }
    }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def reactions
    account = Account.find(params[:userId])
    return render json: [] if collections_hidden?(account, false)
    return render json: [] unless reactions_public?(account)

    scope = StatusReaction.where(account_id: account.id).includes(:status, :custom_emoji).order(id: :desc)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('status_reactions.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    reactions = scope.limit(pagination_limit).select { |reaction| reaction.status && StatusPolicy.new(current_account, reaction.status).show? }

    statuses = reactions.map(&:status)
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: reactions.map { |reaction| serialize_reaction(reaction, account, context) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def featured_notes
    account = Account.find(params[:userId])
    return render json: [] if collections_hidden?(account, false)

    scope = account.statuses
      .where(visibility: [:public, :unlisted], reblog_of_id: nil, in_reply_to_id: nil)
      .joins(:status_stat)
      .where('status_stats.reblogs_count + status_stats.favourites_count > 0')
      .order(id: :desc)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('statuses.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    statuses = scope.limit(pagination_limit).to_a
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)

    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def report_abuse
    target = Account.find(params[:userId])
    ReportService.new.call(current_account, target, comment: params[:comment].to_s)
    head 204
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def pinned_users
    accounts = Account.local.discoverable.order('account_stats.followers_count DESC').limit(pagination_limit)
    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true) }
  end

  private

  def account_relationships(accounts)
    AccountRelationshipsPresenter.new(accounts, current_account.id) if current_account
  end

  def serialize_reaction(reaction, account, context)
    {
      id: MisskeyCompat::MiId.encode(reaction.id),
      createdAt: reaction.created_at.iso8601,
      user: context.user(account),
      type: reaction_type(reaction),
      note: MisskeyCompat::NoteSerializer.serialize(reaction.status, context: context),
    }
  end

  def reactions_public?(account)
    return true if current_account && current_account.id == account.id
    return true unless account.local? && account.user

    account.user.settings['show_reactions'] != false
  end

  def reaction_type(reaction)
    custom = reaction.custom_emoji
    return reaction.name if custom.nil?

    host = custom.domain.presence || '.'
    ":#{reaction.name}@#{host}:"
  end

  def apply_host_filter(scope, host)
    return scope.where(domain: nil) if host.blank? || host.casecmp?(Rails.configuration.x.local_domain)

    scope.where('lower(accounts.domain) LIKE ?', "#{ActiveRecord::Base.sanitize_sql_like(host.downcase)}%")
  end

  def normalized_hostname
    return @normalized_hostname if defined?(@normalized_hostname)

    host = params[:hostname].to_s.strip
    @normalized_hostname = host.present? ? TagManager.instance.normalize_domain(host) : nil
  rescue Addressable::URI::InvalidURIError
    @normalized_hostname = host
  end

  def collections_hidden?(target, hidden)
    target.unavailable? || (hidden && current_account.id != target.id) || target.blocking?(current_account)
  end

  def paginate_follows(scope)
    scope = scope.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    scope = scope.where('follows.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.limit(pagination_limit)
  end

  def statuses_filter_params
    {
      exclude_replies: !ActiveModel::Type::Boolean.new.cast(params[:includeReplies]),
      exclude_reblogs: !ActiveModel::Type::Boolean.new.cast(params.fetch(:withRenotes, true)),
      only_media: ActiveModel::Type::Boolean.new.cast(params[:withFiles]),
    }
  end
end
