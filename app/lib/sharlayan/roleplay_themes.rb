# frozen_string_literal: true

module Sharlayan::RoleplayThemes
  FLAVOURS = %w(glitch glitch-classic).freeze
  DEFAULT_FLAVOUR = 'glitch'

  module_function

  def flavours
    Themes.instance.flavours & FLAVOURS
  end

  def flavour?(flavour)
    flavours.include?(flavour)
  end

  def parse(value)
    value = value.to_s.strip
    return if value.empty?

    flavour, skin = value.include?('/') ? value.split('/', 2) : [DEFAULT_FLAVOUR, value]
    return unless flavour?(flavour) && Themes.instance.skins_for(flavour).include?(skin)

    [flavour, skin]
  end

  def normalize(value)
    parse(value)&.join('/')
  end

  def flavour_for(*candidates)
    candidates.find { |flavour| flavour?(flavour) } || flavours.first
  end
end
