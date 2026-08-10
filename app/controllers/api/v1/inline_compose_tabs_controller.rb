# frozen_string_literal: true

class Api::V1::InlineComposeTabsController < Api::BaseController
  ALLOWED_TYPES = %w(list antenna).freeze

  before_action -> { doorkeeper_authorize! :write, :'write:accounts' }
  before_action :require_user!

  def update
    tabs = normalized_tabs
    current_user.settings[:inline_compose_tabs] = tabs.to_json
    current_user.save!

    render json: { tabs: tabs }
  end

  private

  def normalized_tabs
    tabs = params[:tabs]
    raise Mastodon::InvalidParameterError, "Invalid value for 'tabs'" unless tabs.is_a?(Array) && tabs.size <= 100

    tabs.map do |tab|
      type = tab[:type].to_s
      id = tab[:id].to_s
      raise Mastodon::InvalidParameterError, "Invalid value for 'tabs'" unless ALLOWED_TYPES.include?(type) && id.match?(/\A[1-9]\d*\z/)

      { type: type, id: id }
    end.uniq
  end
end
