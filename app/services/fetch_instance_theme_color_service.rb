# frozen_string_literal: true

class FetchInstanceThemeColorService < BaseService
  NETWORK_ERRORS = [
    HTTP::Error,
    OpenSSL::SSL::SSLError,
    SocketError,
    Addressable::URI::InvalidURIError,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    Errno::ETIMEDOUT,
  ].freeze

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

  def call(domain)
    @domain = domain
    @metadata = InstanceMetadata.for_domain(domain)
    @favicon_from_api = nil

    misskey_meta = fetch_misskey_meta
    misskey_name = fetch_instance_name_from_misskey

    theme_color = extract_theme_color
    favicon_url = extract_favicon_url
    software_info = determine_software_info(misskey_meta)
    instance_name = determine_instance_name(misskey_name)

    local_favicon_path = download_and_save_favicon(favicon_url) if favicon_url.present?

    local_favicon_path ||= generate_blank_favicon if @metadata.favicon_url.blank?

    # Only overwrite a field when we actually obtained a fresh, valid value.
    # A partial fetch failure must never clobber previously stored data, must
    # never persist an external URL, and must never reset the personal color.
    attributes = { metadata_updated_at: Time.now.utc }

    # Theme (personal) color: keep the existing one unless we detected a new
    # color from the homepage. Only fall back to the software default the very
    # first time, when nothing has ever been stored.
    if theme_color.present?
      attributes[:theme_color] = theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    elsif @metadata.theme_color.blank?
      attributes[:theme_color] = @metadata.default_theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    end

    # Favicon: only ever store a locally downloaded path. Never persist a remote
    # URL (it breaks CSP), and keep the existing local copy if the download failed.
    attributes[:favicon_url] = local_favicon_path if local_favicon_path.present?

    # Software / version: keep existing values if detection failed.
    if software_info[:software].present?
      attributes[:software] = software_info[:software]
      attributes[:version] = software_info[:version]
    end

    # Instance name: determine_instance_name falls back to the bare domain, so
    # treat that as "not found" rather than overwriting a real name.
    attributes[:instance_name] = instance_name if instance_name.present? && instance_name != @domain

    # avatarDecorations support: only update when nodeinfo was actually reachable,
    # otherwise we would reset a known-true flag to false on a transient failure.
    attributes[:supports_avatar_decorations] = extract_nodeinfo_features.include?('avatarDecorations') if fetch_nodeinfo.present?

    @metadata.update(attributes)

    @metadata
  rescue *NETWORK_ERRORS
    # Total failure: keep all existing data, only throttle the next refresh.
    @metadata.update(metadata_updated_at: Time.now.utc)

    nil
  end

  private

  def fetch_homepage_html
    @homepage_html ||= begin
      url = "https://#{@domain}"
      request = Request.new(:get, url)
      request.add_headers('User-Agent' => Mastodon::Version.user_agent)
      html = nil
      request.perform do |response|
        html = response.body_with_limit if response.code == 200
      end
      html
    end
  rescue *NETWORK_ERRORS
    nil
  end

  def parsed_homepage
    @parsed_homepage ||= Nokogiri::HTML(fetch_homepage_html) if fetch_homepage_html
  end

  def fetch_nodeinfo
    return @nodeinfo if defined?(@nodeinfo_fetched)

    @nodeinfo_fetched = true
    @nodeinfo = fetch_nodeinfo_uncached
  end

  def extract_theme_color
    return nil unless parsed_homepage

    theme_color_meta = parsed_homepage.at_css('meta[name="theme-color"]')
    return normalize_color(theme_color_meta['content']) if theme_color_meta&.[]('content')

    tile_color_meta = parsed_homepage.at_css('meta[name="msapplication-TileColor"]')
    return normalize_color(tile_color_meta['content']) if tile_color_meta&.[]('content')

    nil
  end

  def extract_favicon_url
    return @favicon_from_api if @favicon_from_api.present?

    return "https://#{@domain}/favicon.ico" unless parsed_homepage

    app_icon = parsed_homepage.at_css('link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]')
    return resolve_url(app_icon['href']) if app_icon&.[]('href') && resolve_url(app_icon['href'])

    favicon_link = parsed_homepage.at_css('link[rel="icon"], link[rel="shortcut icon"]')
    return resolve_url(favicon_link['href']) || "https://#{@domain}/favicon.ico" if favicon_link && favicon_link['href']

    "https://#{@domain}/favicon.ico"
  end

  def extract_nodeinfo_features
    nodeinfo = fetch_nodeinfo
    return [] if nodeinfo.nil?

    features = nodeinfo.dig('metadata', 'features')
    return features if features.is_a?(Array)

    # Also check the boolean shorthand we emit ourselves
    nodeinfo.dig('metadata', 'avatarDecorations') ? ['avatarDecorations'] : []
  rescue
    []
  end

  def determine_software_info(misskey_meta)
    return misskey_meta if misskey_meta[:software].present?

    nodeinfo = fetch_nodeinfo
    if nodeinfo
      return {
        software: nodeinfo.dig('software', 'name'),
        version: nodeinfo.dig('software', 'version'),
      }
    end

    { software: nil, version: nil }
  rescue *NETWORK_ERRORS, JSON::ParserError
    { software: nil, version: nil }
  end

  def determine_instance_name(misskey_name)
    return misskey_name if misskey_name.present?

    nodeinfo = fetch_nodeinfo
    return nodeinfo.dig('metadata', 'nodeName') if nodeinfo && nodeinfo.dig('metadata', 'nodeName').present?

    html_name = extract_instance_name_from_html
    return html_name if html_name.present?

    api_name = fetch_instance_name_from_api
    return api_name if api_name.present?

    @domain
  rescue *NETWORK_ERRORS, JSON::ParserError
    @domain
  end

  def fetch_misskey_meta
    api_url = "https://#{@domain}/nodeinfo/2.1"

    request = Request.new(:get, api_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        meta_data = JSON.parse(response_body)
        software = detect_misskey_software(meta_data)
        version = meta_data['version']

        if software.present?
          return {
            software: software,
            version: version,
          }
        end
      end
    end

    { software: nil, version: nil }
  rescue *NETWORK_ERRORS, JSON::ParserError
    { software: nil, version: nil }
  end

  def fetch_instance_name_from_misskey
    api_url = "https://#{@domain}/api/meta"

    request = Request.new(:post, api_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)
    request.add_headers('Content-Type' => 'application/json')

    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit

        meta_data = JSON.parse(response_body)

        return meta_data['name'] if meta_data['name'].present?

        return meta_data['nodeName'] if meta_data['nodeName'].present?

        @favicon_from_api = meta_data['iconUrl'] if meta_data['iconUrl'].present?
      end
    end

    nil
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def detect_misskey_software(meta_data)
    repo_url = meta_data['repositoryUrl']&.downcase || ''

    return 'sharkey' if repo_url.include?('sharkey')
    return 'firefish' if repo_url.include?('firefish')
    return 'calckey' if repo_url.include?('calckey')
    return 'foundkey' if repo_url.include?('foundkey')
    return 'magnetar' if repo_url.include?('magnetar')
    return 'iceshrimp' if repo_url.include?('iceshrimp')
    return 'catodon' if repo_url.include?('catodon')
    return 'cherrypick' if repo_url.include?('cherrypick')

    version = meta_data['version']&.downcase || ''

    return 'sharkey' if version.include?('sharkey')
    return 'firefish' if version.include?('firefish')
    return 'calckey' if version.include?('calckey')
    return 'cherrypick' if version.include?('cherrypick')

    'misskey'
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
    # Mastodon API v1
    api_url = "https://#{@domain}/api/v1/instance"

    request = Request.new(:get, api_url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        instance_data = JSON.parse(response_body)

        return instance_data['title'] if instance_data['title'].present?
      end
    end

    # Mastodon API v2
    api_v2_url = "https://#{@domain}/api/v2/instance"

    request_v2 = Request.new(:get, api_v2_url)
    request_v2.add_headers('User-Agent' => Mastodon::Version.user_agent)

    request_v2.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        instance_data = JSON.parse(response_body)

        return instance_data['title'] if instance_data['title'].present?
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
        links = nodeinfo_data['links'] || []
        latest_link = links.max_by { |link| link['rel']&.scan(/\d+\.\d+/)&.first.to_f }
        nodeinfo_url = latest_link&.[]('href')
      end
    end

    return nil if nodeinfo_url.nil?

    nodeinfo_request = Request.new(:get, nodeinfo_url)
    nodeinfo_request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    nodeinfo = nil
    nodeinfo_request.perform do |response|
      if response.code == 200
        response_body = response.body_with_limit
        nodeinfo = JSON.parse(response_body)
      end
    end

    nodeinfo
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
  end

  def normalize_color(color)
    return nil if color.blank?

    color = color.strip

    if color.match?(/^#[0-9A-Fa-f]{6}$/)
      return color.upcase
    elsif color.match?(/^#[0-9A-Fa-f]{3}$/)
      return "##{color[1].upcase * 2}#{color[2].upcase * 2}#{color[3].upcase * 2}"
    end

    nil
  end

  def resolve_url(href)
    return href if href.start_with?('http://', 'https://')
    return "https:#{href}" if href.start_with?('//')

    base_url = "https://#{@domain}"
    URI.join(base_url, href).to_s
  rescue URI::InvalidURIError
    nil
  end

  def download_and_save_favicon(favicon_url)
    return nil if favicon_url.blank?

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
