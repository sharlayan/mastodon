# frozen_string_literal: true

class Api::V1::InlineComposeTabsController < Api::BaseController
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
    Sharlayan::InlineComposeTabs.normalize(params[:tabs])
  end
end
