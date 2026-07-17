# frozen_string_literal: true

class Api::V1::Accounts::PagesController < Api::BaseController
  include Api::PagesRoleplayAccessConcern

  before_action :require_feature_enabled!
  before_action -> { authorize_if_got_token! :read, :'read:accounts' }
  before_action :set_account
  before_action :set_page, only: :show

  def index
    cache_if_unauthenticated!
    @pages = load_pages
    render json: @pages, each_serializer: REST::PageSerializer, include_locked_header: true
  end

  def show
    cache_if_unauthenticated!
    render json: @page, serializer: REST::PageSerializer
  end

  private

  def require_feature_enabled!
    not_found unless Setting.pages_enabled
  end

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_page
    not_found if @account.unavailable?
    @page = @account.pages.find_by!(name: params[:name])
    not_found if @page.private_visibility? && @page.account_id != current_account&.id
  end

  def load_pages
    return [] if @account.unavailable?

    @account.pages.listed.order(id: :desc).to_a
  end
end
