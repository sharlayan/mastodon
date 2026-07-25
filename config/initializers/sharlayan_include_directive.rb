# frozen_string_literal: true

require 'jsonapi/include_directive'

module Sharlayan
  module IncludeDirectiveWildcardCache
    def [](key)
      name = key.to_sym
      return @hash[name] if @hash.key?(name)
      return nil unless @options[:allow_wildcard]
      return @sharlayan_deep_wildcard ||= self.class.new({ :** => {} }, @options) if @hash.key?(:**)

      @hash[:*]
    end
  end
end

JSONAPI::IncludeDirective.prepend(Sharlayan::IncludeDirectiveWildcardCache)
