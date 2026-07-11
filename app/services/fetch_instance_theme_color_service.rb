# frozen_string_literal: true

class FetchInstanceThemeColorService < BaseService
  # 그만 고장났으면 좋겠다
  # 테스트 환경에서는 기본적으로 원격 fetch를 건너뜀
  # 필요한 spec만 allow_remote_fetch_in_test로 활성화.
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

    misskey_meta = fetch_misskey_meta
    misskey_name = fetch_instance_name_from_misskey

    theme_color = extract_theme_color
    favicon_url = extract_favicon_url
    software_info = determine_software_info(misskey_meta)
    instance_name = determine_instance_name(misskey_name)

    local_favicon_path = download_and_save_favicon(favicon_url) if favicon_url.present?

    local_favicon_path ||= generate_blank_favicon if @metadata.favicon_url.blank?

    # 새로 얻은 유효한 값일 때만 덮어씀.
    # 부분 실패 시 기존 데이터를 절대 훼손하지 않음.
    attributes = { metadata_updated_at: Time.now.utc }

    # 테마색: 기존 값 유지. 업데이트 실패 시 기본색으로 돌아가는 것 방지 처리
    # 최초 fetch일 때만 소프트웨어 기본색으로 적용.
    if theme_color.present?
      attributes[:theme_color] = theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    elsif @metadata.theme_color.blank?
      attributes[:theme_color] = @metadata.default_theme_color
      attributes[:theme_color_updated_at] = Time.now.utc
    end

    # 파비콘: 로컬에 다운로드한 경로만 저장(원격 URL은 CSP 위반) - 원격 주소 그대로 쓰는 경우가 종종 있었음.
    # 실패 시 기존 값 유지.
    attributes[:favicon_url] = local_favicon_path if local_favicon_path.present?

    # 소프트웨어 / 버전: 감지 실패 시 기존 값 유지.
    if software_info[:software].present?
      attributes[:software] = software_info[:software]
      attributes[:version] = software_info[:version]
    end

    # 도메인 자체가 반환되면 "찾지 못함"을 의미
    # 실제 이름을 도메인으로 덮어쓰지 않음.
    attributes[:instance_name] = instance_name if instance_name.present? && instance_name != @domain

    # nodeinfo가 도달 가능했을 때만 갱신, 아니면 일시적 실패가 known-true 플래그를 초기화함.
    if fetch_nodeinfo.present?
      nodeinfo_features = extract_nodeinfo_features
      attributes[:supports_avatar_decorations] = nodeinfo_features.include?('avatarDecorations')
      attributes[:features] = nodeinfo_features
    end

    @metadata.update(attributes)

    @metadata
  rescue *NETWORK_ERRORS
    # 완전 실패: 기존 데이터는 유지하고 다음 갱신만 스로틀.
    @metadata.update(metadata_updated_at: Time.now.utc)

    nil
  end

  private

  def skip_remote_fetch?
    Rails.env.test? && !self.class.allow_remote_fetch_in_test
  end

  # kmyblue 포크에서 차용한 기능. 전달 실패 서버는 탐색 안 함.
  def domain_unavailable?
    unavailable_domains_map = Rails.cache.fetch('unavailable_domains') { UnavailableDomain.pluck(:domain).index_with(true) }
    unavailable_domains_map[@domain].present?
  end

  def throttle_only!
    @metadata.update(metadata_updated_at: Time.now.utc)
    @metadata
  end

  # 테스트 전용 경로: HTTP 없이 기본값만 기록하고 다음 갱신을 스로틀.
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

    candidates = icons.select { |icon| icon.is_a?(Hash) && icon['src'].present? }
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
    url = "https://#{@domain}/manifest.json"

    request = Request.new(:get, url)
    request.add_headers('User-Agent' => Mastodon::Version.user_agent)

    manifest = nil
    request.perform do |response|
      manifest = JSON.parse(response.body_with_limit) if response.code == 200
    end

    manifest
  rescue *NETWORK_ERRORS, JSON::ParserError
    nil
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
    return misskey_name if usable_instance_name?(misskey_name)

    nodeinfo = fetch_nodeinfo
    nodeinfo_name = nodeinfo&.dig('metadata', 'nodeName')
    return nodeinfo_name if usable_instance_name?(nodeinfo_name)

    html_name = extract_instance_name_from_html
    return html_name if usable_instance_name?(html_name)

    api_name = fetch_instance_name_from_api
    return api_name if usable_instance_name?(api_name)

    @domain
  rescue *NETWORK_ERRORS, JSON::ParserError
    @domain
  end

  def usable_instance_name?(name)
    name.present? && !generic_instance_name?(name)
  end

  def generic_instance_name?(name)
    GENERIC_INSTANCE_NAME_PATTERNS.any? { |pattern| name.match?(pattern) }
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

        @favicon_from_api = resolve_url(meta_data['iconUrl']) if meta_data['iconUrl'].present?

        return meta_data['name'] if meta_data['name'].present?

        return meta_data['nodeName'] if meta_data['nodeName'].present?
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
