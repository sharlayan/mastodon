# frozen_string_literal: true

require 'singleton'
require 'yaml'

class Themes
  include Singleton

  THEME_COLORS = {
    dark: '#181820',
    light: '#ffffff',
  }.freeze
  COLOR_SCHEMES = %w(auto light dark).freeze

  def initialize
    @flavours = {}

    Rails.root.glob('app/javascript/flavours/*/theme.yml') do |pathname|
      data = YAML.load_file(pathname)
      next unless data['pack_directory']

      dir = pathname.dirname
      name = dir.basename.to_s
      locales = []
      screenshots = []

      if data['locales']
        Dir.glob(File.join(dir, data['locales'], '*.{js,json}')) do |locale|
          locale_name = File.basename(locale, File.extname(locale))
          locales.push(locale_name) unless /defaultMessages|whitelist|index/.match?(locale_name)
        end
      end

      if data['screenshot']
        if data['screenshot'].is_a? Array
          screenshots = data['screenshot']
        else
          screenshots.push(data['screenshot'])
        end
      end

      data['name'] = name
      data['locales'] = locales
      data['screenshot'] = screenshots
      data['skins'] = []
      @flavours[name] = data
    end

    Rails.root.glob('app/javascript/skins/*/*') do |pathname|
      ext = pathname.extname.to_s
      skin = pathname.basename.to_s
      name = pathname.dirname.basename.to_s
      next unless @flavours[name]

      if pathname.directory?
        @flavours[name]['skins'] << skin if pathname.glob('{common,index,application}.{css,scss}').any?
      elsif /^\.s?css$/i.match?(ext)
        @flavours[name]['skins'] << pathname.basename(ext).to_s
      end
    end
  end

  def flavour(name)
    @flavours[name]
  end

  def flavours
    @flavours.keys
  end

  def skins_for(name)
    skins = @flavours[name]['skins']
    skins.include?('default') && skins.include?('mastodon-light') ? ['system'] + skins : skins
  end

  def supported_color_schemes(flavour, skin)
    return COLOR_SCHEMES unless @flavours.key?(flavour)
    return COLOR_SCHEMES unless skins_for(flavour).include?(skin)

    configured = @flavours.dig(flavour, 'skin_color_schemes', skin)
    schemes = Array(configured).map(&:to_s) & COLOR_SCHEMES
    schemes.presence || COLOR_SCHEMES
  end

  def resolve_color_scheme(flavour, skin, requested)
    supported = supported_color_schemes(flavour, skin)
    requested = requested.to_s
    return requested if supported.include?(requested)
    return 'dark' if supported.include?('dark') && !supported.include?('light')
    return 'light' if supported.include?('light') && !supported.include?('dark')

    supported.first || 'auto'
  end

  def flavours_and_skins
    flavours.map do |flavour|
      [flavour, skins_for(flavour).map { |skin| [flavour, skin] }]
    end
  end
end
