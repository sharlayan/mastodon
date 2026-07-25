# frozen_string_literal: true

module Admin
  class AvatarDecorationsController < BaseController
    before_action :set_decoration, only: [:edit, :update, :destroy, :approve, :redownload]

    def index
      authorize :avatar_decoration, :index?

      params.delete(:by_domain) if params[:local].present?
      if params[:by_domain].present?
        params.delete(:local)
        params[:remote] = '1'
      end

      @decorations = filtered_decorations.page(params[:page])
      @form        = Form::AvatarDecorationBatch.new
    end

    def new
      authorize :avatar_decoration, :create?
      @decoration = AvatarDecoration.new
    end

    def edit
      authorize :avatar_decoration, :update?
    end

    def create
      authorize :avatar_decoration, :create?

      @decoration = AvatarDecoration.new(decoration_params)
      @decoration.approved = true

      if @decoration.save
        log_action :create, @decoration
        redirect_to admin_avatar_decorations_path, notice: I18n.t('admin.avatar_decorations.created_msg')
      else
        render :new
      end
    end

    def update
      authorize :avatar_decoration, :update?
      raise Mastodon::NotPermittedError unless @decoration.local?

      if @decoration.update(decoration_params)
        log_action :update, @decoration
        redirect_to admin_avatar_decorations_path, notice: I18n.t('admin.avatar_decorations.updated_msg')
      else
        render :edit
      end
    end

    def destroy
      authorize :avatar_decoration, :destroy?
      @decoration.destroy!
      log_action :destroy, @decoration
      redirect_to admin_avatar_decorations_path, notice: I18n.t('admin.avatar_decorations.destroyed_msg')
    end

    def approve
      authorize :avatar_decoration, :update?
      @decoration.update!(approved: true)
      log_action :update, @decoration
      redirect_to admin_avatar_decorations_path, notice: I18n.t('admin.avatar_decorations.approved_msg')
    end

    def redownload
      authorize :avatar_decoration, :update?
      raise Mastodon::NotPermittedError if @decoration.local?

      @decoration.download_image!
      if @decoration.save
        log_action :update, @decoration
        redirect_to edit_admin_avatar_decoration_path(@decoration), notice: I18n.t('admin.avatar_decorations.redownloaded_msg')
      else
        redirect_to edit_admin_avatar_decoration_path(@decoration), alert: I18n.t('admin.avatar_decorations.redownload_failed_msg')
      end
    end

    def check_images
      authorize :avatar_decoration, :update?

      CheckAvatarDecorationImagesWorker.perform_async

      redirect_to admin_avatar_decorations_path(filter_params), notice: I18n.t('admin.avatar_decorations.check_images_msg')
    end

    def batch
      authorize :avatar_decoration, :index?

      @form = Form::AvatarDecorationBatch.new(
        form_avatar_decoration_batch_params.merge(current_account: current_account, action: action_from_button)
      )
      @form.save
    rescue ActionController::ParameterMissing
      flash[:alert] = I18n.t('admin.avatar_decorations.no_decoration_selected')
    rescue Mastodon::NotPermittedError
      flash[:alert] = I18n.t('admin.not_permitted')
    ensure
      redirect_to admin_avatar_decorations_path(filter_params)
    end

    private

    def set_decoration
      @decoration = AvatarDecoration.find(params[:id])
    end

    def decoration_params
      permitted = params.expect(avatar_decoration: [:name, :description, :image, :required_role_id, :category_id, :category_name])
      category_name = permitted.delete(:category_name)

      permitted[:category_id] = AvatarDecorationCategory.find_or_create_by!(name: category_name.strip).id if category_name.present?

      permitted
    end

    def filtered_decorations
      scope = AvatarDecoration.order(created_at: :desc)

      if params[:local] == '1'
        scope = scope.local
      elsif params[:remote] == '1'
        scope = scope.remote
        scope = scope.where(host: params[:by_domain]) if params[:by_domain].present?
      end

      case params[:status]
      when 'approved'
        scope = scope.approved
      when 'pending'
        scope = scope.pending_approval
      end

      scope
    end

    def filter_params
      params.slice(:page, :local, :remote, :by_domain, :status).permit(:page, :local, :remote, :by_domain, :status)
    end

    def action_from_button
      if params[:approve]
        'approve'
      elsif params[:delete]
        'delete'
      elsif params[:update]
        'update'
      end
    end

    def form_avatar_decoration_batch_params
      params.expect(form_avatar_decoration_batch: [:category_id, :category_name, avatar_decoration_ids: []])
    end
  end
end
