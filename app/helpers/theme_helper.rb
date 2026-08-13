# frozen_string_literal: true

module ThemeHelper
  include RoleplayModeHelper

  def javascript_inline_tag(path)
    entry = InlineScriptManager.instance.file(path)

    # Only add hash if we don't allow arbitrary includes already, otherwise it's going
    # to break the React Tools browser extension or other inline scripts
    unless Rails.env.development? && request.content_security_policy.dup.script_src.include?("'unsafe-inline'")
      request.content_security_policy = request.content_security_policy.clone.tap do |policy|
        values = policy.script_src
        values << "'sha256-#{entry[:digest]}'"
        policy.script_src(*values)
      end
    end

    content_tag(:script, entry[:contents], type: 'text/javascript')
  end

  def theme_style_tags(flavour_and_skin, **)
    flavour, theme = flavour_and_skin

    vite_stylesheet_tag "skins/#{flavour}/#{theme}", type: :virtual, media: 'all', crossorigin: 'anonymous', **
  end

  def theme_color_tags(color_scheme)
    case color_scheme
    when 'auto'
      ''.html_safe.tap do |tags|
        tags << tag.meta(name: 'theme-color', content: Themes::THEME_COLORS[:dark], media: '(prefers-color-scheme: dark)')
        tags << tag.meta(name: 'theme-color', content: Themes::THEME_COLORS[:light], media: '(prefers-color-scheme: light)')
      end
    when 'light'
      tag.meta name: 'theme-color', content: Themes::THEME_COLORS[:light]
    when 'dark'
      tag.meta name: 'theme-color', content: Themes::THEME_COLORS[:dark]
    end
  end

  def custom_stylesheet
    return if active_custom_stylesheet.blank?

    stylesheet_link_tag(
      custom_css_path(active_custom_stylesheet),
      host: root_url,
      media: :all,
      skip_pipeline: true
    )
  end

  def server_css?
    current_user.nil? || current_user.setting_use_server_css
  end

  def user_custom_css?
    Setting.allow_user_custom_css && current_user.present? && current_user.setting_use_custom_css && current_user.custom_css_text.present?
  end

  def user_custom_stylesheet
    return if current_user.nil?

    stylesheet_link_tag(
      user_custom_css_path(version: current_user.custom_css&.updated_at&.to_i),
      host: root_url,
      media: :all,
      skip_pipeline: true
    )
  end

  def current_flavour
    return 'glitch' if roleplay_mode? && Themes.instance.flavours.include?('glitch')

    [current_user&.setting_flavour, Setting.flavour, 'glitch', 'vanilla'].find { |flavour| Themes.instance.flavours.include?(flavour) }
  end

  def current_skin
    skins = Themes.instance.skins_for(current_flavour)
    [roleplay_forced_skin, current_user&.setting_skin, Setting.skin, 'default'].compact.find { |skin| skins.include?(skin) }
  end

  def roleplay_forced_skin
    Setting.roleplay_forced_skin.presence if roleplay_mode?
  end

  def current_theme
    # NOTE: this is slightly different from upstream, as it's a derived value used
    # for the sole purpose of pointing to the appropriate stylesheet pack
    [current_flavour, current_skin]
  end

  def color_scheme
    current_user&.setting_color_scheme || 'auto'
  end

  def contrast
    current_user&.setting_contrast || 'auto'
  end

  def page_color_scheme
    requested = content_for(:force_color_scheme).presence || color_scheme
    Themes.instance.resolve_color_scheme(current_flavour, active_page_skin, requested)
  end

  def active_page_skin
    (respond_to?(:page_blog_view_skin) && page_blog_view_skin.presence) || current_skin
  end

  def active_supported_color_schemes
    Themes.instance.supported_color_schemes(current_flavour, active_page_skin)
  end

  def skin_label(flavour, skin)
    label = I18n.t("skins.#{flavour}.#{skin}", default: skin)
    schemes = Themes.instance.supported_color_schemes(flavour, skin)
    schemes == ['dark'] ? "#{label} (#{I18n.t('themes.dark_only')})" : label
  end

  def supported_color_scheme_collection
    user_settings_collection('web.color_scheme') & active_supported_color_schemes
  end

  private

  def active_custom_stylesheet
    return if cached_custom_css_digest.blank?

    [:custom, cached_custom_css_digest.to_s.first(8)]
      .compact_blank
      .join('-')
  end

  def cached_custom_css_digest
    Rails.cache.fetch(:setting_digest_custom_css) do
      Setting.custom_css&.then { |content| Digest::SHA256.hexdigest(content) }
    end
  end
end
