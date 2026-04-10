# frozen_string_literal: true

module Admin
  class AvatarDecorationDomainBlocksController < BaseController
    def index
      authorize :avatar_decoration_domain_block, :index?
      @domain_blocks = AvatarDecorationDomainBlock.order(created_at: :desc).page(params[:page])
    end

    def create
      authorize :avatar_decoration_domain_block, :create?

      @domain_block = AvatarDecorationDomainBlock.new(domain_block_params)

      if @domain_block.save
        log_action :create, @domain_block
        redirect_to admin_avatar_decoration_domain_blocks_path,
                    notice: I18n.t('admin.avatar_decoration_domain_blocks.created_msg')
      else
        @domain_blocks = AvatarDecorationDomainBlock.order(created_at: :desc).page(params[:page])
        render :index
      end
    end

    def destroy
      authorize :avatar_decoration_domain_block, :destroy?
      @domain_block = AvatarDecorationDomainBlock.find(params[:id])
      @domain_block.destroy!
      log_action :destroy, @domain_block
      redirect_to admin_avatar_decoration_domain_blocks_path,
                  notice: I18n.t('admin.avatar_decoration_domain_blocks.destroyed_msg')
    end

    private

    def domain_block_params
      params.expect(avatar_decoration_domain_block: [:domain])
    end
  end
end
