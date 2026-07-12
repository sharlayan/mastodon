# frozen_string_literal: true

class Api::MisskeyCompat::HashtagsController < Api::MisskeyCompat::BaseController
  before_action :require_user!

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

    render json: accounts.map { |account| MisskeyCompat::UserSerializer.serialize(account, detailed: true, viewer: current_account) }
  end

  private

  def serialize_tag(tag)
    {
      tag: tag.name,
      mentionedUsersCount: 0,
      mentionedLocalUsersCount: 0,
      mentionedRemoteUsersCount: 0,
      attachedUsersCount: tag.accounts.count,
      attachedLocalUsersCount: tag.accounts.local.count,
      attachedRemoteUsersCount: tag.accounts.remote.count,
    }
  end

  def recent_uses(tag)
    tag.history.get(Time.now.utc).accounts.to_i
  rescue
    0
  end
end
