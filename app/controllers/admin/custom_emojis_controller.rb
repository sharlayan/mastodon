# frozen_string_literal: true

module Admin
  class CustomEmojisController < BaseController
    def index
      authorize :custom_emoji, :index?

      # If filtering by domain, ensure remote filter is set.
      if params[:by_domain].present?
        params.delete(:local)
        params[:remote] = '1'
      end

      @custom_emojis = filtered_custom_emojis.eager_load(:local_counterpart).page(params[:page])
      @form          = Form::CustomEmojiBatch.new
    end

    def new
      authorize :custom_emoji, :create?

      @custom_emoji = CustomEmoji.new
    end

    def edit
      authorize :custom_emoji, :update?

      @custom_emoji = CustomEmoji.find(params[:id])
      redirect_to admin_custom_emojis_path, alert: I18n.t('admin.custom_emojis.not_permitted') unless @custom_emoji.local?
    end

    def create
      authorize :custom_emoji, :create?

      @custom_emoji = CustomEmoji.new(resource_params)

      if @custom_emoji.save
        log_action :create, @custom_emoji
        redirect_to admin_custom_emojis_path, notice: I18n.t('admin.custom_emojis.created_msg')
      else
        render :new
      end
    end

    def update
      authorize :custom_emoji, :update?

      @custom_emoji = CustomEmoji.find(params[:id])
      return redirect_to admin_custom_emojis_path, alert: I18n.t('admin.custom_emojis.not_permitted') unless @custom_emoji.local?

      # The shortcode is the emoji's identity (referenced by existing posts and
      # federation), so it must not be mutated after creation.
      if @custom_emoji.update(resource_params.except(:shortcode))
        log_action :update, @custom_emoji
        purge_emoji_cache
        redirect_to admin_custom_emojis_path, notice: I18n.t('admin.custom_emojis.updated_msg')
      else
        render :edit
      end
    end

    def bulk_edit
      authorize :custom_emoji, :update?

      scope = CustomEmoji.local.order(:shortcode)
      scope = scope.search(params[:shortcode]) if params[:shortcode].present?

      @custom_emojis = scope.page(params[:page]).per(50)
      @categories    = CustomEmojiCategory.alphabetic.all
    end

    BULK_UPDATE_LIMIT = 200

    def bulk_update
      authorize :custom_emoji, :update?

      updated = 0
      failed  = 0

      entries = bulk_emoji_update_params.first(BULK_UPDATE_LIMIT)

      ActiveRecord::Base.transaction do
        entries.each do |id, attrs|
          emoji = CustomEmoji.local.find_by(id: id)
          next unless emoji

          update_attrs = {
            aliases: attrs[:aliases_raw].to_s.split(',').map(&:strip).reject(&:empty?),
            license: attrs[:license],
            category_id: attrs[:category_id].presence,
          }

          if emoji.update(update_attrs)
            log_action :update, emoji
            updated += 1
          else
            failed += 1
          end
        end
      end

      if failed.positive?
        flash[:alert] = I18n.t('admin.custom_emojis.bulk_update_partial', updated: updated, failed: failed)
      else
        purge_emoji_cache
        flash[:notice] = I18n.t('admin.custom_emojis.bulk_updated_msg', count: updated)
      end

      redirect_to bulk_edit_admin_custom_emojis_path(page: params[:page], shortcode: params[:shortcode])
    end

    def reset_cache
      authorize :custom_emoji, :index?

      Rails.cache.delete('api/v1/custom_emojis')
      Rails.cache.delete_matched('emoji:*')

      redirect_to admin_custom_emojis_path, notice: I18n.t('admin.custom_emojis.reset_cache_done_msg')
    end

    def batch
      authorize :custom_emoji, :index?

      @form = Form::CustomEmojiBatch.new(form_custom_emoji_batch_params.merge(current_account: current_account, action: action_from_button))
      @form.save
    rescue ActionController::ParameterMissing
      flash[:alert] = I18n.t('admin.custom_emojis.no_emoji_selected')
    rescue Mastodon::NotPermittedError
      flash[:alert] = I18n.t('admin.custom_emojis.not_permitted')
    rescue ActiveRecord::RecordInvalid => e
      error_message = action_from_button == 'copy' ? 'admin.custom_emojis.batch_copy_error' : 'admin.custom_emojis.batch_error'
      flash[:alert] = I18n.t(error_message, message: e.message)
    ensure
      redirect_to admin_custom_emojis_path(filter_params)
    end

    private

    def bulk_emoji_update_params
      return {} if params[:emojis].blank?

      emoji_ids = params[:emojis].keys.grep(/\A\d+\z/)
      emoji_ids.each_with_object({}) do |id, result|
        attrs = params[:emojis][id]
        next unless attrs.is_a?(ActionController::Parameters)

        result[id] = attrs.permit(:aliases_raw, :license, :category_id)
      end
    end

    def purge_emoji_cache
      Rails.cache.delete('api/v1/custom_emojis')
      Rails.cache.delete_matched('emoji:*')
    end

    def resource_params
      permitted = params
        .expect(custom_emoji: [:shortcode, :image, :visible_in_picker, :is_sensitive, :local_only, :license, :aliases_raw])

      if permitted[:aliases_raw]
        permitted[:aliases] = permitted.delete(:aliases_raw)
          .split(',')
          .map(&:strip)
          .reject(&:empty?)
      end

      permitted
    end

    def filtered_custom_emojis
      CustomEmojiFilter.new(filter_params).results
    end

    def filter_params
      params.slice(:page, *CustomEmojiFilter::KEYS).permit(:page, *CustomEmojiFilter::KEYS)
    end

    def action_from_button
      if params[:update]
        'update'
      elsif params[:list]
        'list'
      elsif params[:unlist]
        'unlist'
      elsif params[:enable]
        'enable'
      elsif params[:disable]
        'disable'
      elsif params[:copy]
        'copy'
      elsif params[:delete]
        'delete'
      end
    end

    def form_custom_emoji_batch_params
      params
        .expect(form_custom_emoji_batch: [:action, :category_id, :category_name, custom_emoji_ids: []])
    end
  end
end
