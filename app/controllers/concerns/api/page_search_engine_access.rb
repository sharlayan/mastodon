# frozen_string_literal: true

module Api::PageSearchEngineAccess
  extend ActiveSupport::Concern

  private

  def page_hidden_from_search_engine?(account)
    current_account.nil? && search_engine_crawler? && account.user_prefers_noindex? != false
  end

  def search_engine_crawler?
    @search_engine_crawler ||= request.user_agent.present? && Browser.new(request.user_agent).bot?
  end
end
