# frozen_string_literal: true

class Api::MisskeyCompat::HashtagsController < Api::MisskeyCompat::BaseController
  include Api::AccountRateLimit

  SEARCH_QUERY_LENGTH_LIMIT = StatusLengthValidator::MAX_CHARS
  SEARCH_OFFSET_LIMIT = 1_000

  requires_misskey_permission 'read:account', :index, :trend, :search, :show, :users

  SORT_ORDERS = {
    '+attachedUsers' => Arel.sql('attached_users_count DESC, tags.name ASC'),
    '-attachedUsers' => Arel.sql('attached_users_count ASC, tags.name ASC'),
    '+attachedLocalUsers' => Arel.sql('attached_local_users_count DESC, tags.name ASC'),
    '-attachedLocalUsers' => Arel.sql('attached_local_users_count ASC, tags.name ASC'),
    '+attachedRemoteUsers' => Arel.sql('attached_remote_users_count DESC, tags.name ASC'),
    '-attachedRemoteUsers' => Arel.sql('attached_remote_users_count ASC, tags.name ASC'),
    '+mentionedUsers' => nil,
    '-mentionedUsers' => nil,
    '+mentionedLocalUsers' => nil,
    '-mentionedLocalUsers' => nil,
    '+mentionedRemoteUsers' => nil,
    '-mentionedRemoteUsers' => nil,
  }.freeze

  before_action :require_user!
  before_action :enforce_hashtag_rate_limit!

  def index
    sort = params[:sort].to_s
    return render_invalid_param('#/properties/sort', 'unsupported sort') unless SORT_ORDERS.key?(sort)

    tags = Tag.listable
      .left_joins(:accounts)
      .group('tags.id')
      .select(
        'tags.*',
        'COUNT(accounts.id) AS attached_users_count',
        'COUNT(CASE WHEN accounts.domain IS NULL THEN 1 END) AS attached_local_users_count',
        'COUNT(CASE WHEN accounts.domain IS NOT NULL THEN 1 END) AS attached_remote_users_count'
      )
    tags = tags.having('COUNT(accounts.id) > 0') if boolean_param?(:attachedToUserOnly)
    tags = tags.having('COUNT(CASE WHEN accounts.domain IS NULL THEN 1 END) > 0') if boolean_param?(:attachedToLocalUserOnly)
    tags = tags.having('COUNT(CASE WHEN accounts.domain IS NOT NULL THEN 1 END) > 0') if boolean_param?(:attachedToRemoteUserOnly)

    order = SORT_ORDERS.fetch(sort)
    tags = tags.order(order || { name: :asc })
    tags = tags.limit(pagination_limit(default: 10, max: 100)).to_a

    render json: tags.map { |tag| serialize_tag(tag) }
  end

  def trend
    return render json: [] unless Setting.trends

    tags = Trends.tags.query.allowed.limit(pagination_limit)

    render json: tags.map { |tag|
      {
        tag: tag.name,
        chart: [],
        usersCount: recent_uses(tag),
      }
    }
  end

  def search
    query = params[:query].to_s.strip.delete_prefix('#')
    return render json: [] if query.blank? || query.length > SEARCH_QUERY_LENGTH_LIMIT

    tags = Tag.search_for(query, pagination_limit, params[:offset].to_i.clamp(0, SEARCH_OFFSET_LIMIT), exclude_unreviewed: false)

    render json: tags.pluck(:name)
  end

  def show
    tag = Tag.find_normalized(params[:tag].to_s)
    render_error('No such hashtag', 'NO_SUCH_HASHTAG', 404) and return if tag.nil?

    render json: serialize_tag(tag)
  end

  def users
    tag = Tag.find_normalized(params[:tag].to_s)
    return render json: [] if tag.nil?

    scope = apply_user_origin(tag.accounts.discoverable.without_suspended)
    accounts = apply_user_sort(scope).limit(pagination_limit).to_a
    relationships = AccountRelationshipsPresenter.new(accounts, current_account.id)

    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: current_account, relationships: relationships) }
  end

  private

  def enforce_hashtag_rate_limit!
    enforce_account_rate_limit!(:misskey_hashtags)
  rescue Mastodon::RateLimitExceededError
    render_error(I18n.t('errors.429'), 'RATE_LIMIT_EXCEEDED', 429)
  end

  def serialize_tag(tag)
    attached_users_count, attached_local_users_count, attached_remote_users_count = attached_counts(tag)

    {
      tag: tag.name,
      mentionedUsersCount: 0,
      mentionedLocalUsersCount: 0,
      mentionedRemoteUsersCount: 0,
      attachedUsersCount: attached_users_count,
      attachedLocalUsersCount: attached_local_users_count,
      attachedRemoteUsersCount: attached_remote_users_count,
    }
  end

  def attached_counts(tag)
    if tag.has_attribute?(:attached_users_count)
      [tag[:attached_users_count].to_i, tag[:attached_local_users_count].to_i, tag[:attached_remote_users_count].to_i]
    else
      [tag.accounts.count, tag.accounts.local.count, tag.accounts.remote.count]
    end
  end

  def boolean_param?(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def recent_uses(tag)
    tag.history.get(Time.now.utc).accounts.to_i
  rescue
    0
  end
end
