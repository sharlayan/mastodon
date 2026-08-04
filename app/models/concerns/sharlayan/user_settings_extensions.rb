# frozen_string_literal: true

module Sharlayan::UserSettingsExtensions
  class << self
    def apply(settings)
      apply_root_settings(settings)
      apply_web_settings(settings)
      apply_notification_settings(settings)
      apply_avatar_decoration_settings(settings)
      apply_cat_settings(settings)
    end

    private

    def apply_root_settings(settings)
      settings.setting :auto_accept_followed, default: false
      settings.setting :show_reactions, default: true
      settings.setting :hide_online_status, default: true
      settings.setting :prevent_ai_learning, default: false
      settings.setting :norss, default: -> { ::Setting.norss }
      settings.setting :visible_reactions, default: 6
      settings.setting :bridge_unlisted_to_bsky, default: false
      settings.setting :auto_quote_from_url, default: false
      settings.setting :misskey_muted_words, default: '[]'
      settings.setting :misskey_hard_muted_words, default: '[]'
      settings.setting :drive_keep_original_filename, default: true
      settings.setting :drive_default_folder_id, default: nil
      settings.setting :drive_upload_original_image, default: true
      settings.setting_inverse_alias :show_online_status, :hide_online_status
      settings.setting_inverse_alias :enable_rss, :norss
    end

    def apply_web_settings(settings)
      settings.namespace :web do
        setting :custom_emoji_size, default: false
        setting :reaction_custom_emoji_size, default: false
        setting :mfm_force_sensitive, default: false
        setting :mfm_enabled, default: false
        setting :mfm_animations, default: false
        setting :mfm_fold_mode, default: 'sensitive', in: %w(show sensitive all)
        setting :custom_emoji_mute_hidden, default: false
        setting :pages_view, default: 'list', in: %w(list blog)
        setting :pages_blog_list_position, default: 'left', in: %w(left right)
        setting :ignore_others_pages_view, default: false
        setting :use_server_css, default: true
        setting :use_custom_css, default: false
      end
    end

    def apply_notification_settings(settings)
      settings.namespace :notification_emails do
        setting :reaction, default: false
      end
    end

    def apply_avatar_decoration_settings(settings)
      settings.namespace :avatar_decorations do
        setting :show, default: false
        setting :show_federated, default: false
        setting :shape, default: 'none', in: %w(none round square)
      end
    end

    def apply_cat_settings(settings)
      settings.namespace :cat do
        setting :show, default: true
        setting :show_speak, default: true
        setting :show_federated, default: true
      end
    end
  end
end
