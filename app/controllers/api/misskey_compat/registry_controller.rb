# frozen_string_literal: true

class Api::MisskeyCompat::RegistryController < Api::MisskeyCompat::BaseController
  before_action :require_user!

  SCOPE_PATTERN = /\A[a-zA-Z0-9_]+\z/

  def get_all # rubocop:disable Naming/AccessorMethodName
    render json: scoped_items.to_h { |item| [item.key, item.value] }
  end

  def get
    item = find_item
    return render_no_such_key if item.nil?

    render json: item.value.to_json
  end

  def get_detail # rubocop:disable Naming/AccessorMethodName
    item = find_item
    return render_no_such_key if item.nil?

    render json: { updatedAt: item.updated_at.iso8601(3), value: item.value }
  end

  def set
    key = registry_key
    raise ArgumentError, 'value is required' unless registry_body.key?('value')

    item = find_item || current_account.misskey_registry_items.new(domain: effective_domain, scope: registry_scope, key: key)
    item.update!(value: registry_body['value'])

    head 204
  end

  def remove
    item = find_item
    return render_no_such_key if item.nil?

    item.destroy!
    head 204
  end

  def keys
    render json: scoped_items.map(&:key)
  end

  def keys_with_type
    render json: scoped_items.to_h { |item| [item.key, value_type(item.value)] }
  end

  def scopes_with_domain
    res = []

    current_account.misskey_registry_items.pluck(:domain, :scope).each do |domain, scope|
      target = res.find { |entry| entry[:domain] == domain }

      if target
        target[:scopes] << scope unless target[:scopes].include?(scope)
      else
        res << { domain: domain, scopes: [scope] }
      end
    end

    render json: res
  end

  private

  def scoped_items
    current_account.misskey_registry_items.where(domain: effective_domain, scope: registry_scope)
  end

  def find_item
    scoped_items.find_by(key: registry_key)
  end

  def registry_body
    @registry_body ||= begin
      raw = request.raw_post
      raw.blank? ? {} : JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end
  end

  def registry_scope
    raw = registry_body['scope']
    return [] if raw.nil?
    raise ArgumentError, 'scope must be an array' unless raw.is_a?(Array)

    raw.map do |entry|
      entry.to_s.tap do |str|
        raise ArgumentError, 'scope items must match [a-zA-Z0-9_]+' unless str.match?(SCOPE_PATTERN)
      end
    end
  end

  def effective_domain
    registry_body['domain']&.to_s.presence
  end

  def registry_key
    key = registry_body['key'].to_s
    raise ArgumentError, 'key is required' if key.empty?

    key
  end

  def value_type(value)
    case value
    when nil then 'null'
    when Array then 'array'
    when Numeric then 'number'
    when String then 'string'
    when true, false then 'boolean'
    else 'object'
    end
  end

  def render_no_such_key
    render_error('No such key.', 'NO_SUCH_KEY', 404) # rubocop:disable I18n/RailsI18n/DecorateString
  end
end
