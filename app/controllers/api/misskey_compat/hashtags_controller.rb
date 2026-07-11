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

  private

  def recent_uses(tag)
    tag.history.get(Time.now.utc).accounts.to_i
  rescue
    0
  end
end
