# frozen_string_literal: true

class Api::MisskeyCompat::ListsController < Api::MisskeyCompat::BaseController
  before_action :require_user!
  before_action :set_list!, only: [:show, :update, :destroy, :push, :pull, :timeline, :memberships]

  def index
    render json: current_account.owned_lists.order(id: :desc).map { |list| serialize(list) }
  end

  def show
    render json: serialize(@list)
  end

  def create
    list = current_account.owned_lists.create!(title: params[:name].to_s)
    render json: serialize(list)
  end

  def create_from_public
    render_error('Importing public lists is not supported on this server', 'UNSUPPORTED_ENDPOINT', 501, kind: 'server')
  end

  def update
    @list.update!(title: params[:name].to_s) if params[:name].present?
    render json: serialize(@list)
  end

  def destroy
    @list.destroy!
    head 204
  end

  def push
    account = Account.find_by(id: params[:userId])
    return render_error('No such user', 'NO_SUCH_USER', 404) if account.nil?
    return render_error('You can only add users you follow', 'NOT_FOLLOWING', 400) unless account.id == current_account.id || current_account.following?(account)

    AddAccountsToListService.new.call(@list, Account.where(id: account.id))
    head 204
  end

  def pull
    RemoveAccountsFromListService.new.call(@list, Account.where(id: params[:userId]))
    head 204
  end

  def timeline
    statuses = ListFeed.new(@list).get(pagination_limit, params[:untilId].presence, params[:sinceId].presence).to_a
    Status.preload_cacheable_associations(statuses)
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  def memberships
    members = @list.list_accounts.includes(:account).order(id: :desc)
    members = members.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    members = members.limit(pagination_limit)

    render json: members.map { |la|
      { id: MisskeyCompat::MiId.encode(la.id), createdAt: la.created_at.iso8601, userId: MisskeyCompat::MiId.encode(la.account_id), user: MisskeyCompat::UserSerializer.serialize(la.account) }
    }
  end

  private

  def set_list!
    @list = current_account.owned_lists.find(params[:listId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such list', 'NO_SUCH_LIST', 404)
  end

  def serialize(list)
    {
      id: MisskeyCompat::MiId.encode(list.id),
      createdAt: list.created_at.iso8601,
      name: list.title,
      isPublic: false,
      userIds: list.accounts.pluck(:id).map { |id| MisskeyCompat::MiId.encode(id) },
    }
  end
end
