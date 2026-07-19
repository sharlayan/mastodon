# frozen_string_literal: true

class Api::MisskeyCompat::HashtagsController < Api::MisskeyCompat::BaseController
  SORT_COLUMNS = {
    '+attachedUsers' => ['attached_users_count', 'DESC'],
    '-attachedUsers' => ['attached_users_count', 'ASC'],
    '+attachedLocalUsers' => ['attached_local_users_count', 'DESC'],
    '-attachedLocalUsers' => ['attached_local_users_count', 'ASC'],
    '+attachedRemoteUsers' => ['attached_remote_users_count', 'DESC'],
    '-attachedRemoteUsers' => ['attached_remote_users_count', 'ASC'],
    '+mentionedUsers' => [nil, nil],
    '-mentionedUsers' => [nil, nil],
    '+mentionedLocalUsers' => [nil, nil],
    '-mentionedLocalUsers' => [nil, nil],
    '+mentionedRemoteUsers' => [nil, nil],
    '-mentionedRemoteUsers' => [nil, nil],
  }.freeze

  before_action :require_user!

  def index
    sort = params[:sort].to_s
    return render_invalid_param('#/properties/sort', 'unsupported sort') unless SORT_COLUMNS.key?(sort)

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

    column, direction = SORT_COLUMNS.fetch(sort)
    tags = column ? tags.order(Arel.sql("#{column} #{direction}, tags.name ASC")) : tags.order(name: :asc)
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
    return render json: [] if query.blank?

    tags = Tag.search_for(query, pagination_limit, params[:offset].to_i, exclude_unreviewed: false)

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
