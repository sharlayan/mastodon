# frozen_string_literal: true

module Sharlayan::REST::Account::RequestScopedCache
  extend ActiveSupport::Concern

  WILDCARD_INCLUDE_KEYS = [:**].freeze
  STORE_KEY = :sharlayan_serialized_accounts

  def serializable_hash(adapter_options = nil, options = {}, adapter_instance = self.class.serialization_adapter_instance)
    id = object.id if object.respond_to?(:id)
    return super if id.nil? || !RequestStore.active?
    return super unless default_serialization_options?(adapter_options, options)

    store = RequestStore.store[STORE_KEY] ||= {}
    key = [self.class, object.class, id, request_scoped_cache_viewer_id]
    cached = store[key]
    return cached.dup if cached

    store[key] = super
    store[key].dup
  end

  private

  def default_serialization_options?(adapter_options, options)
    return false unless options[:fields].nil?

    adapter_options ||= {}
    fieldset = adapter_options[:fieldset]
    return false if fieldset && !fieldset.fields.empty?

    directive = options[:include_directive] || ActiveModel::Serializer.include_directive_from_options(adapter_options)
    directive.keys == WILDCARD_INCLUDE_KEYS
  end

  def request_scoped_cache_viewer_id
    current_user&.id if respond_to?(:current_user)
  end
end
