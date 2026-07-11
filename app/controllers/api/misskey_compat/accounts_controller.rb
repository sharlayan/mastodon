# frozen_string_literal: true

class Api::MisskeyCompat::AccountsController < Api::MisskeyCompat::BaseController
  before_action :require_user!, only: [:followers, :following]

  def notes
    account = Account.find(params[:userId])
    filter = AccountStatusesFilter.new(account, current_account, statuses_filter_params)
    statuses = filter.results.to_a_paginated_by_id(pagination_limit, max_id: params[:untilId].presence, since_id: params[:sinceId].presence).to_a
    Status.preload_cacheable_associations(statuses)

    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account) }
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

    render json: reactions.map { |reaction| serialize_reaction(reaction, account) }
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

    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, current_account: current_account) }
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end

  def report_abuse
    require_user! and return if current_account.nil?

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

  def serialize_reaction(reaction, account)
    {
      id: MisskeyCompat::MiId.encode(reaction.id),
      createdAt: reaction.created_at.iso8601,
      user: MisskeyCompat::UserSerializer.serialize(account),
      type: reaction_type(reaction),
      note: MisskeyCompat::NoteSerializer.serialize(reaction.status, current_account: current_account),
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
