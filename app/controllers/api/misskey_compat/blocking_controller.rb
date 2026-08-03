# frozen_string_literal: true

class Api::MisskeyCompat::BlockingController < Api::MisskeyCompat::BaseController
  requires_write_scope :create, :destroy
  requires_misskey_permission 'read:blocks', :index
  requires_misskey_permission 'write:blocks', :create, :destroy

  before_action :require_user!
  before_action :set_target!, only: [:create, :destroy]

  def index
    blocks = paginated_blocks.to_a
    relationships = AccountRelationshipsPresenter.new(blocks.map(&:target_account), current_account.id)
    render json: blocks.map { |block| serialize(block, relationships) }
  end

  def create
    BlockService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true, viewer: current_account)
  end

  def destroy
    UnblockService.new.call(current_account, @target)
    render json: MisskeyCompat::UserSerializer.serialize(@target, detailed: true, viewer: current_account)
  end

  private

  def serialize(block, relationships)
    {
      id: MisskeyCompat::MiId.encode(block.id),
      createdAt: block.created_at.iso8601,
      blockeeId: MisskeyCompat::MiId.encode(block.target_account_id),
      blockee: MisskeyCompat::UserSerializer.serialize(block.target_account, detailed: true, viewer: current_account, relationships: relationships),
    }
  end

  def paginated_blocks
    scope = current_account.block_relationships.includes(:target_account).order(id: :desc)
    scope = scope.where(id: ...params[:untilId].to_i) if params[:untilId].present?
    scope = scope.where('blocks.id > ?', params[:sinceId].to_i) if params[:sinceId].present?
    scope.limit(pagination_limit(default: 30, max: 100))
  end

  def set_target!
    @target = Account.without_requested_deletion.find(params[:userId])
  rescue ActiveRecord::RecordNotFound
    render_error('No such user', 'NO_SUCH_USER', 404)
  end
end
