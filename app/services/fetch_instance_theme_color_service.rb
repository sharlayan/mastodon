# frozen_string_literal: true

class FetchInstanceThemeColorService < BaseService
  @allow_remote_fetch_in_test = false

  class << self
    attr_accessor :allow_remote_fetch_in_test
  end

  NETWORK_ERRORS = [
    HTTP::Error,
    OpenSSL::SSL::SSLError,
    SocketError,
    Addressable::URI::InvalidURIError,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    Errno::ETIMEDOUT,
    Mastodon::LengthValidationError,
  ].freeze

  INSTANCE_NAME_MAX_LENGTH = 100

  ALLOWED_FAVICON_CONTENT_TYPES = %w(
    image/png
    image/x-icon
    image/vnd.microsoft.icon
    image/gif
    image/jpeg
    image/webp
  ).freeze

  CONTENT_TYPE_TO_EXT = {
    'image/png' => '.png',
    'image/x-icon' => '.ico',
    'image/vnd.microsoft.icon' => '.ico',
    'image/gif' => '.gif',
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
  }.freeze

  GENERIC_INSTANCE_NAME_PATTERNS = [
    /\bmastodon\s+hosted\s+(?:on|by|at)\b/i,
    /에서\s*호스팅\s*되는\s*마스토돈/,
    /에서\s*운영\s*되는\s*마스토돈/,
  ].freeze

  def call(domain)
    @domain = domain
    @metadata = InstanceMetadata.for_domain(domain)
    @favicon_from_api = nil

    return skip_remote_fetch! if skip_remote_fetch?
    return throttle_only! if domain_unavailable?

    nodeinfo = fetch_nodeinfo
    misskey_meta = fetch_misskey_meta(nodeinfo)

    theme_color = extract_theme_color(nodeinfo)
    favicon_url = extract_favicon_url
    software_info = determine_software_info(nodeinfo)
    instance_name = determine_instance_name(nodeinfo, misskey_meta)

    local_favicon_path = download_and_save_favicon(favicon_url) if favicon_url.present?

    local_favicon_path ||= generate_blank_favicon if @metadata.favicon_url.blank?

    attributes = { metadata_updated_at: Time.now.utc }

    if theme_color.present?
      attributes[:theme_color] = theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    elsif @metadata.theme_color.blank?
      attributes[:theme_color] = @metadata.default_theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    end

    attributes[:favicon_url] = local_favicon_path if local_favicon_path.present?

    if software_info[:software].present?
      attributes[:software] = software_info[:software]
      attributes[:version] = software_info[:version]
    end

    attributes[:instance_name] = instance_name if instance_name.present? && instance_name != @domain

    if nodeinfo.present?
      wire_features = extract_nodeinfo_features
      attributes[:supports_avatar_decorations] = wire_features.include?('avatarDecorations')
      attributes[:features] = InstanceMetadata.features_from_wire(wire_features)
    end

    @metadata.update(attributes)

    @metadata
  rescue *NETWORK_ERRORS
    @metadata.update(metadata_updated_at: Time.now.utc)

    nil
  end

  private

  def skip_remote_fetch?
    Rails.env.test? && !self.class.allow_remote_fetch_in_test
  end

  def domain_unavailable?
    unavailable_domains_map = Rails.cache.fetch('unavailable_domains') { UnavailableDomain.pluck(:domain).index_with(true) }
    unavailable_domains_map[@domain].present?
  end

  def throttle_only!
    @metadata.update(metadata_updated_at: Time.now.utc)
    @metadata
  end

  def skip_remote_fetch!
    attributes = { metadata_updated_at: Time.now.utc }

    if @metadata.theme_color.blank?
      attributes[:theme_color] = @metadata.default_theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    end

    @metadata.update(attributes)
    @metadata
  end

  def fetch_homepage_html
    return @homepage_html if defined?(@homepage_fetched)

    @homepage_fetched = true
    @homepage_html = nil
    @homepage_charset = nil

    url = "https://#{@domain}"
    request = Request.new(:get, url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)
    request.perform do |response|
      if response.code == 200
        @homepage_charset = response.charset
        @homepage_html = response.body_with_limit
      end
    end

    @homepage_html
  rescue *NETWORK_ERRORS
    @homepage_html = nil
  end

  def parsed_homepage
    return @parsed_homepage if defined?(@parsed_homepage)

    html = fetch_homepage_html
    @parsed_homepage = html.present? ? Nokogiri::HTML(html, nil, detect_html_encoding(html)) : nil
  end

  def detect_html_encoding(html)
    [header_encoding(@homepage_charset), charlock_encoding(html)].compact.each do |enc|
      return enc if html.dup.force_encoding(enc).valid_encoding?
    end

    nil
  end

  def charlock_encoding(html)
    guess = encoding_detector.detect(html, @homepage_charset)
    return nil if guess.nil?

    guess[:confidence].to_i > 60 ? guess[:encoding] : nil
  end

  def header_encoding(charset)
    return nil if charset.blank?

    Encoding.find(charset).name
  rescue ArgumentError
    nil
  end

  def encoding_detector
    @encoding_detector ||= CharlockHolmes::EncodingDetector.new.tap do |detector|
      detector.strip_tags = true
    end
  end

  def fetch_nodeinfo
    return @nodeinfo if defined?(@nodeinfo_fetched)

    @nodeinfo_fetched = true
    @nodeinfo = fetch_nodeinfo_uncached
  end

  def extract_theme_color(nodeinfo)
    nodeinfo_color = nodeinfo_metadata(nodeinfo)['themeColor']
    color = normalize_color(nodeinfo_color)
    return color if color.present?

    if parsed_homepage
      theme_color_meta = parsed_homepage.at_css('meta[name="theme-color"]')
      color = normalize_color(theme_color_meta['content']) if theme_color_meta&.[]('content')
      return color if color.present?

      tile_color_meta = parsed_homepage.at_css('meta[name="msapplication-TileColor"]')
      color = normalize_color(tile_color_meta['content']) if tile_color_meta&.[]('content')
      return color if color.present?
    end

    manifest = fetch_manifest
    normalize_color(manifest['theme_color']) if manifest.is_a?(Hash)
  end

  def extract_favicon_url
    return @favicon_from_api if @favicon_from_api.present?

    manifest_icon = extract_icon_from_manifest
    return manifest_icon if manifest_icon.present?

    return "https://#{@domain}/favicon.ico" unless parsed_homepage

    app_icon = last_icon_href('link[rel~="apple-touch-icon-precomposed"]') || last_icon_href('link[rel~="apple-touch-icon"]')
    return app_icon if app_icon.present?

    favicon_link = last_icon_href('link[rel~="icon"]')
    return favicon_link || "https://#{@domain}/favicon.ico" if favicon_link.present?

    "https://#{@domain}/favicon.ico"
  end

  def last_icon_href(selector)
    return nil unless parsed_homepage

    link = parsed_homepage.css(selector).to_a.reverse.find { |node| node['href'].present? }
    return nil if link.nil?

    resolved = resolve_url(link['href'])
    return nil if resolved.blank? || resolved.start_with?('data:')

    resolved
  end

  def extract_icon_from_manifest
    manifest = fetch_manifest
    return nil if manifest.nil?

    icons = manifest['icons']
    return nil unless icons.is_a?(Array)

    candidates = icons.select { |icon| icon.is_a?(Hash) && icon['src'].is_a?(String) && icon['src'].present? }
    return nil if candidates.empty?

    best = candidates.max_by { |icon| manifest_icon_area(icon['sizes']) }
    src = best['src']

    resolved = resolve_url(src)
    return nil if resolved.blank? || resolved.start_with?('data:')

    resolved
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def manifest_icon_area(sizes)
    return 0 if sizes.blank?

    sizes.to_s.split.filter_map do |size|
      match = size.match(/\A(\d+)x(\d+)\z/i)
      match ? match[1].to_i * match[2].to_i : nil
    end.max || 0
  end

  def fetch_manifest
    return @manifest if defined?(@manifest_fetched)

    @manifest_fetched = true
    @manifest = fetch_manifest_uncached
  end

  def fetch_manifest_uncached
    manifest_urls.each do |url|
      request = Request.new(:get, url)
      request.add_headers('User-Agent' => Mastodon::Version.user_agent)

      manifest = nil
      request.perform do |response|
        manifest = JSON.parse(response.body_with_limit) if response.code == 200
      end

      return manifest if manifest.is_a?(Hash)
    rescue *NETWORK_ERRORS, JSON::ParserError
      next
    end

    nil
  end

  def manifest_urls
    manifest_link = parsed_homepage&.css('link[rel~="manifest"]')&.to_a&.reverse&.find { |node| node['href'].present? }
    resolved = resolve_url(manifest_link['href']) if manifest_link

    [resolved, "https://#{@domain}/manifest.json"].compact.uniq
  end

  def extract_nodeinfo_features
    nodeinfo = fetch_nodeinfo
    return [] if nodeinfo.nil?

    features = nodeinfo.dig('metadata', 'features')
    return features if features.is_a?(Array)

    nodeinfo.dig('metadata', 'avatarDecorations') ? ['avatarDecorations'] : []
  rescue
    []
  end

  def determine_software_info(nodeinfo)
    software_info = nodeinfo_software(nodeinfo)
    software = software_info['name']
    version = software_info['version']

    {
      software: software.is_a?(String) ? software.downcase : nil,
      version: version.is_a?(String) ? version : nil,
    }
  end

  def determine_instance_name(nodeinfo, misskey_meta)
    metadata = nodeinfo_metadata(nodeinfo)
    name = normalize_instance_name(metadata['nodeName'])
    return name if usable_instance_name?(name)

    name = normalize_instance_name(metadata['name'])
    return name if usable_instance_name?(name)

    name = normalize_instance_name(extract_open_graph_title)
    return name if usable_instance_name?(name)

    name = normalize_instance_name(manifest_instance_name)
    return name if usable_instance_name?(name)

    name = normalize_instance_name(misskey_meta&.[]('name') || misskey_meta&.[]('nodeName'))
    return name if usable_instance_name?(name)

    name = normalize_instance_name(fetch_instance_name_from_api)
    return name if usable_instance_name?(name)

    name = normalize_instance_name(extract_instance_name_from_html)
    return name if usable_instance_name?(name)

    @domain
  rescue *NETWORK_ERRORS, JSON::ParserError
    @domain
  end

  def normalize_instance_name(name)
    return nil unless name.is_a?(String)

    text = name.to_s
    text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '') unless text.encoding == Encoding::UTF_8
    text = text.scrub('').gsub(/\s+/, ' ').strip

    return nil if text.blank?

    text.truncate(INSTANCE_NAME_MAX_LENGTH)
  end

  def usable_instance_name?(name)
    name.present? && !generic_instance_name?(name)
  end

  def generic_instance_name?(name)
    GENERIC_INSTANCE_NAME_PATTERNS.any? { |pattern| name.match?(pattern) }
  end

  def fetch_misskey_meta(nodeinfo)
    software = nodeinfo_software(nodeinfo)['name']
    return nil unless software.is_a?(String) && %w(misskey sharkey firefish calckey foundkey magnetar iceshrimp catodon cherrypick).include?(software.downcase)

    api_url = "https://#{@domain}/api/meta"

    request = Request.new(:post, api_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)
    request.add_headers('Content-Type' => 'application/json')

    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit

        meta_data = JSON.parse(response_body)
        return nil unless meta_data.is_a?(Hash)

        @favicon_from_api = resolve_url(meta_data['iconUrl']) if meta_data['iconUrl'].is_a?(String) && meta_data['iconUrl'].present?
        return meta_data
      end
    end

    nil
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def extract_open_graph_title
    return nil unless parsed_homepage

    parsed_homepage.at_css('meta[property="og:title"]')&.[]('content')
  end

  def manifest_instance_name
    manifest = fetch_manifest
    return nil unless manifest.is_a?(Hash)

    name = manifest['name']
    return name if name.is_a?(String)

    short_name = manifest['short_name']
    short_name if short_name.is_a?(String)
  end

  def extract_instance_name_from_html
    return nil unless parsed_homepage

    og_site_name = parsed_homepage.at_css('meta[property="og:site_name"]')
    return og_site_name['content'] if og_site_name&.[]('content')

    app_name = parsed_homepage.at_css('meta[name="application-name"]')
    return app_name['content'] if app_name&.[]('content')

    title = parsed_homepage.at_css('title')
    return title.text.strip if title&.text.present?

    nil
  end

  def fetch_instance_name_from_api
    api_url = "https://#{@domain}/api/v1/instance"

    request = Request.new(:get, api_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        instance_data = JSON.parse(response_body)

        return instance_data['title'] if instance_data.is_a?(Hash) && instance_data['title'].is_a?(String) && instance_data['title'].present?
      end
    end

    api_v2_url = "https://#{@domain}/api/v2/instance"

    request_v2 = Request.new(:get, api_v2_url)
    request_v2.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request_v2.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        instance_data = JSON.parse(response_body)

        return instance_data['title'] if instance_data.is_a?(Hash) && instance_data['title'].is_a?(String) && instance_data['title'].present?
      end
    end
    nil
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def fetch_nodeinfo_uncached
    well_known_url = "https://#{@domain}/.well-known/nodeinfo"

    request = Request.new(:get, well_known_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    nodeinfo_url = nil
    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        nodeinfo_data = JSON.parse(response_body)
        links = nodeinfo_data['links'] if nodeinfo_data.is_a?(Hash)
        nodeinfo_url = preferred_nodeinfo_url(links)
      end
    end

    return nil if nodeinfo_url.nil?

    nodeinfo_request = Request.new(:get, nodeinfo_url)
    nodeinfo_request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    nodeinfo = nil
    nodeinfo_request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        parsed = JSON.parse(response_body)
        nodeinfo = parsed if parsed.is_a?(Hash)
      end
    end

    nodeinfo
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def preferred_nodeinfo_url(links)
    return nil unless links.is_a?(Array)

    supported_relations = %w(
      http://nodeinfo.diaspora.software/ns/schema/2.1
      http://nodeinfo.diaspora.software/ns/schema/2.0
      http://nodeinfo.diaspora.software/ns/schema/1.0
    )

    supported_relations.each do |relation|
      link = links.find { |candidate| candidate.is_a?(Hash) && candidate['rel'] == relation && candidate['href'].is_a?(String) }
      return link['href'] if link
    end

    nil
  end

  def nodeinfo_metadata(nodeinfo)
    metadata = nodeinfo['metadata'] if nodeinfo.is_a?(Hash)
    metadata.is_a?(Hash) ? metadata : {}
  end

  def nodeinfo_software(nodeinfo)
    software = nodeinfo['software'] if nodeinfo.is_a?(Hash)
    software.is_a?(Hash) ? software : {}
  end

  def normalize_color(color)
    return nil unless color.is_a?(String) && color.present?

    color = color.strip

    if color.match?(/^#[0-9A-Fa-f]{6}$/)
      return color.upcase
    elsif color.match?(/^#[0-9A-Fa-f]{3}$/)
      return "##{color[1].upcase * 2}#{color[2].upcase * 2}#{color[3].upcase * 2}"
    end

    nil
  end

  def resolve_url(href)
    return nil unless href.is_a?(String)

    return href if href.start_with?('http://', 'https://')
    return "https:#{href}" if href.start_with?('//')

    base_url = "https://#{@domain}"
    URI.join(base_url, href).to_s
  rescue URI::InvalidURIError
    nil
  end

  def download_and_save_favicon(favicon_url)
    return nil if favicon_url.blank?
    return nil if favicon_url.start_with?('data:')

    begin
      URI.parse(favicon_url)
    rescue URI::InvalidURIError
      return nil
    end

    domain_digest = Digest::SHA1.hexdigest(@domain.to_s)

    storage_path = Rails.public_path.join('system', 'instance_favicons').expand_path
    FileUtils.mkdir_p(storage_path)

    request = Request.new(:get, favicon_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request.perform do |response|
      next unless response.code == 200

      content_type = response.headers['content-type']&.split(';')&.first&.strip&.downcase
      next unless ALLOWED_FAVICON_CONTENT_TYPES.include?(content_type)

      ext = CONTENT_TYPE_TO_EXT[content_type] || '.ico'
      filename = "#{domain_digest}#{ext}"
      file_path = storage_path.join(filename).expand_path

      next unless file_path.to_s.start_with?("#{storage_path}/")

      content = response.body_with_limit
      File.binwrite(file_path, content)

      return "/system/instance_favicons/#{filename}"
    end

    nil
  rescue *NETWORK_ERRORS, Errno::ENOENT, Errno::EACCES
    nil
  end

  def generate_blank_favicon
    domain_digest = Digest::SHA1.hexdigest(@domain.to_s)

    storage_path = Rails.public_path.join('system', 'instance_favicons').expand_path
    FileUtils.mkdir_p(storage_path)

    filename = "#{domain_digest}.png"
    file_path = storage_path.join(filename).expand_path

    return nil unless file_path.to_s.start_with?("#{storage_path}/")

    image = Vips::Image.black(64, 64, bands: 4)
    image.pngsave(file_path.to_s)

    "/system/instance_favicons/#{filename}"
  rescue Vips::Error, Errno::ENOENT, Errno::EACCES
    nil
  end
end
