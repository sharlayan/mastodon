# frozen_string_literal: true

class Api::MisskeyCompat::ListsController < Api::MisskeyCompat::BaseController
  PUBLIC_READ_ACTIONS = %i(index show memberships).freeze

  requires_write_scope :create, :update, :destroy, :push, :pull, :update_membership, :favorite, :unfavorite, :create_from_public
  requires_misskey_permission 'read:account', :index, :show, :timeline, :memberships
  requires_misskey_permission 'write:account', :create, :update, :destroy, :push, :pull, :update_membership, :favorite, :unfavorite, :create_from_public

  before_action :require_user!, except: PUBLIC_READ_ACTIONS
  before_action :require_user_if_authenticated!, only: PUBLIC_READ_ACTIONS
  before_action :prohibit_moved_account!, only: :create_from_public
  before_action :set_list!, only: [:show, :update, :destroy, :push, :pull, :timeline, :memberships, :update_membership]
  before_action :set_public_list!, only: [:favorite, :unfavorite]

  def index
    lists = index_scope
    return if performed?

    lists = lists.order(id: :desc).to_a
    members = ListAccount.joins(:account).where(list_id: lists.map(&:id)).pluck(:list_id, :account_id).group_by(&:first)
    public_ids = MisskeyUserListSetting.public_list_ids(lists.map(&:id))
    render json: lists.map { |list| serialize(list, account_ids: members.fetch(list.id, []).map(&:last), public_ids: public_ids) }
  end

  def show
    data = serialize(@list)
    if public_lookup?
      data[:likedCount] = MisskeyUserListFavorite.where(list: @list).count
      data[:isLiked] = current_account.present? && MisskeyUserListFavorite.exists?(list: @list, account: current_account)
    end
    render json: data
  end

  def favorite
    return render_error('The list has already been favorited.', 'ALREADY_FAVORITED', 400, id: '6425bba0-985b-461e-af1b-518070e72081') if MisskeyUserListFavorite.exists?(list: @list, account: current_account) # rubocop:disable I18n/RailsI18n/DecorateString

    MisskeyUserListFavorite.create!(list: @list, account: current_account)
    head 204
  rescue ActiveRecord::RecordNotUnique
    render_error('The list has already been favorited.', 'ALREADY_FAVORITED', 400, id: '6425bba0-985b-461e-af1b-518070e72081') # rubocop:disable I18n/RailsI18n/DecorateString
  end

  def unfavorite
    favorite = MisskeyUserListFavorite.find_by(list: @list, account: current_account)
    return render_error('You have not favorited the list.', 'ALREADY_FAVORITED', 400, id: '835c4b27-463d-4cfa-969b-a9058678d465') if favorite.nil? # rubocop:disable I18n/RailsI18n/DecorateString

    favorite.destroy!
    head 204
  end

  def create
    list = current_account.owned_lists.create!(title: params[:name].to_s)
    render json: serialize(list)
  end

  def create_from_public
    return render_invalid_param('#/properties/name', 'must be a string of 1 to 100 characters') unless params[:name].is_a?(String) && params[:name].length.between?(1, 100)

    source = public_lists.find_by(id: params[:listId])
    return render_error('No such list.', 'NO_SUCH_LIST', 404, id: '9292f798-6175-4f7d-93f4-b6742279667d') if source.nil? # rubocop:disable I18n/RailsI18n/DecorateString
    return render_error('You cannot create user list any more.', 'TOO_MANY_USERLISTS', 400, id: 'e9c105b2-c595-47de-97fb-7f7c2c33e92f') if current_account.owned_lists.count >= List::PER_ACCOUNT_LIMIT # rubocop:disable I18n/RailsI18n/DecorateString

    member_ids = Account.without_requested_deletion.where(id: source.list_accounts.select(:account_id)).pluck(:id)
    other_ids = member_ids - [current_account.id]
    return render_error('You cannot push this user because you have been blocked by this user.', 'YOU_HAVE_BEEN_BLOCKED', 400, id: 'a2497f2a-2389-439c-8626-5298540530f4') if Block.exists?(account_id: other_ids, target_account_id: current_account.id) # rubocop:disable I18n/RailsI18n/DecorateString

    addable_ids = member_ids & ([current_account.id] + current_account.active_relationships.where(target_account_id: other_ids).pluck(:target_account_id) + current_account.follow_requests.where(target_account_id: other_ids).pluck(:target_account_id))
    list = List.transaction do
      current_account.owned_lists.create!(title: params[:name]).tap do |created|
        AddAccountsToListService.new.call(created, Account.where(id: addable_ids))
      end
    end
    render json: serialize(list)
  end

  def update
    return render_invalid_param('#/properties/isPublic', 'must be boolean') unless params[:isPublic].nil? || [true, false].include?(params[:isPublic])

    List.transaction do
      @list.update!(title: params[:name].to_s) if params[:name].present?
      MisskeyUserListSetting.update_public!(@list, params[:isPublic]) unless params[:isPublic].nil?
    end
    render json: serialize(@list)
  end

  def destroy
    @list.destroy!
    head 204
  end

  def push
    account = Account.without_requested_deletion.find_by(id: params[:userId])
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
    context = MisskeyCompat::SerializationContext.for(statuses, current_account: current_account)
    render json: statuses.map { |status| MisskeyCompat::NoteSerializer.serialize(status, context: context) }
  end

  def memberships
    members = @list.list_accounts.includes(:account, :follow, :follow_request).order(id: :desc)
    members = members.where(id: ...(params[:untilId].to_i)) if params[:untilId].present?
    members = members.limit(pagination_limit)

    render json: members.map { |la|
      { id: MisskeyCompat::MiId.encode(la.id), createdAt: membership_created_at(la).utc.iso8601, userId: MisskeyCompat::MiId.encode(la.account_id), user: MisskeyCompat::UserSerializer.serialize(la.account), withReplies: la.with_replies }
    }
  end

  def update_membership
    account = Account.without_requested_deletion.find_by(id: params[:userId])
    return render_error('No such user', 'NO_SUCH_USER', 404, id: '588e7f72-c744-4a61-b180-d354e912bda2') if account.nil?

    membership = @list.list_accounts.find_by(account: account)
    return render_error('User is not a member of the list', 'NO_SUCH_MEMBERSHIP', 404) if membership.nil?

    return render_invalid_param('#/properties/withReplies/type', 'must be boolean') unless params[:withReplies].nil? || [true, false].include?(params[:withReplies])

    membership.update!(with_replies: params[:withReplies]) unless params[:withReplies].nil?
    head 204
  end

  private

  def membership_created_at(list_account)
    list_account.follow&.created_at || list_account.follow_request&.created_at || @list.created_at
  end

  def set_list!
    @list = (public_lookup? ? public_lists : current_account.owned_lists).find_by(id: params[:listId])
    render_error('No such list', 'NO_SUCH_LIST', 404) if @list.nil?
  end

  def set_public_list!
    @list = public_lists.find_by(id: params[:listId])
    render_error('No such user list.', 'NO_SUCH_USER_LIST', 404, id: action_name == 'favorite' ? '7dbaf3cf-7b42-4b8f-b431-b3919e580dbe' : 'baedb33e-76b8-4b0c-86a8-9375c0a7b94b') if @list.nil? # rubocop:disable I18n/RailsI18n/DecorateString
  end

  def public_lookup?
    PUBLIC_READ_ACTIONS.include?(action_name.to_sym) && (current_account.nil? || params[:forPublic] == true)
  end

  def public_lists
    List.joins(:account).merge(Account.without_suspended.without_requested_deletion).where(id: MisskeyUserListSetting.public_lists.select(:list_id))
  end

  def index_scope
    if params[:userId].nil?
      return current_account.owned_lists if current_account

      return render_error('Invalid param.', 'INVALID_PARAM', 400, id: 'ab36de0e-29e9-48cb-9732-d82f1281620d') # rubocop:disable I18n/RailsI18n/DecorateString
    end

    account = Account.without_requested_deletion.find_by(id: params[:userId])
    return render_error('No such user.', 'NO_SUCH_USER', 404, id: 'a8af4a82-0980-4cc4-a6af-8b0ffd54465e') if account.nil? # rubocop:disable I18n/RailsI18n/DecorateString
    return render_error("Not allowed to load the remote user's list", 'REMOTE_USER_NOT_ALLOWED', 400, id: '53858f1b-3315-4a01-81b7-db9b48d4b79a') unless account.local?

    public_lists.where(account: account)
  end

  def serialize(list, account_ids: nil, public_ids: nil)
    {
      id: MisskeyCompat::MiId.encode(list.id),
      createdAt: list.created_at.iso8601,
      name: list.title,
      userIds: (account_ids || list.accounts.pluck(:id)).map { |id| MisskeyCompat::MiId.encode(id) },
      isPublic: public_ids ? public_ids.include?(list.id) : MisskeyUserListSetting.public_lists.exists?(list: list),
    }
  end
end
