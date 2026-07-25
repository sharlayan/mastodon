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

  module SerializerCollectionCache
    def cache_read_multi(collection_serializer, adapter_instance, include_directive)
      return {} unless sharlayan_serializer_caching_used?

      super
    end

    def sharlayan_serializer_caching_used?
      return @sharlayan_serializer_caching_used if defined?(@sharlayan_serializer_caching_used)

      @sharlayan_serializer_caching_used = ActiveModel::Serializer.descendants.any? do |serializer|
        serializer.cache_enabled? || serializer.fragment_cache_enabled?
      end
    end
  end

  module SerializerScopeReader
    def current_user
      scope
    end
  end
end

JSONAPI::IncludeDirective.prepend(Sharlayan::IncludeDirectiveWildcardCache)
ActiveModel::Serializer.singleton_class.prepend(Sharlayan::SerializerCollectionCache)
ActiveModel::Serializer.include(Sharlayan::SerializerScopeReader)
