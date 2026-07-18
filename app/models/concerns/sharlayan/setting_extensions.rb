# frozen_string_literal: true

module Sharlayan::SettingExtensions
  module_function

  def merge_defaults(defaults)
    defaults.merge(sharlayan_defaults)
  end

  def sharlayan_defaults
    content = Rails.root.join('config', 'settings', 'sharlayan.yml').read
    YAML.safe_load(content).fetch('defaults')
  end
end
