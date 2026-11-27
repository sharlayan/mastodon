# frozen_string_literal: true

module BrandingHelper
  CSS_URL_ESCAPES = {
    '\\' => '%5C',
    "'" => '%27',
    '"' => '%22',
    '(' => '%28',
    ')' => '%29',
    '<' => '%3C',
    '>' => '%3E',
    '&' => '\26 ',
  }.freeze

  def render_logo
    image_tag(frontend_asset_path('images/logo.svg'), alt: 'Mastodon', class: 'logo logo--icon')
  end

  def logo_as_symbol_icon
    inline_svg_tag 'logo-symbol-icon.svg', class: 'logo logo--icon', view_box: '0 0 79 79'
  end

  def logo_as_symbol_wordmark
    inline_svg_tag 'logo-symbol-wordmark.svg', class: 'logo logo--wordmark', title: 'Mastodon'
  end

  def branding_logo_styles
    icon_url = instance_presenter.logo_icon&.file&.url
    dark_wordmark_url = instance_presenter.logo_wordmark_dark&.file&.url || instance_presenter.logo_wordmark_light&.file&.url
    light_wordmark_url = instance_presenter.logo_wordmark_light&.file&.url || instance_presenter.logo_wordmark_dark&.file&.url

    rules = []
    if icon_url
      escaped_icon_url = branding_logo_css_url(icon_url)
      rules << "html{--branding-logo-icon:url(#{escaped_icon_url});--logo:url(#{escaped_icon_url})!important}svg.logo--icon{background:var(--branding-logo-icon) center/contain no-repeat}svg.logo--icon *{display:none}img.logo--icon{content:var(--branding-logo-icon)}"
    end

    if dark_wordmark_url && light_wordmark_url
      escaped_dark_url = branding_logo_css_url(dark_wordmark_url)
      escaped_light_url = branding_logo_css_url(light_wordmark_url)
      rules << 'html{--branding-navigation-logo-display:block}'
      rules << "html{--branding-logo-wordmark:url(#{escaped_dark_url})}html[data-color-scheme=light]{--branding-logo-wordmark:url(#{escaped_light_url})}svg.logo--wordmark{background:var(--branding-logo-wordmark) center/contain no-repeat}svg.logo--wordmark *{display:none}"
      rules << "@media(prefers-color-scheme:light){html:not([data-color-scheme]){--branding-logo-wordmark:url(#{escaped_light_url})}}"
    end

    tag.style(safe_join(rules), nonce: request.content_security_policy_nonce) if rules.any?
  end

  private

  def branding_logo_css_url(url)
    url.gsub(/[\\'"()<>&\s]/) { |character| CSS_URL_ESCAPES.fetch(character, '%20') }
  end
end
