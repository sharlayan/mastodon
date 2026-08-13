# frozen_string_literal: true

module Sharlayan::SettingExtensions
  module_function

  def merge_defaults(defaults)
    defaults.merge(sharlayan_defaults)
  end

  def sharlayan_defaults
    content = Rails.root.join('config', 'settings', 'sharlayan.yml').read
    defaults = YAML.safe_load(content).fetch('defaults')
    defaults['status_character_limit'] = ENV.fetch('MAX_TOOT_CHARS', defaults.fetch('status_character_limit')).to_i
    defaults
  end
end
