# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_registry_items
#
#  id         :bigint(8)        not null, primary key
#  domain     :string
#  key        :string           default(""), not null
#  scope      :string           default([]), not null, is an Array
#  value      :jsonb
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint(8)        not null
#
class MisskeyRegistryItem < ApplicationRecord
  MAX_ITEMS = 1_000
  MAX_SCOPE_ITEMS = 256
  MAX_VALUE_BYTES = 256.kilobytes
  MAX_SCOPE_BYTES = 1.megabyte
  MAX_ACCOUNT_BYTES = 8.megabytes

  belongs_to :account

  validates :key, presence: true, length: { maximum: 1024 }
  validate :validate_storage_limits

  def value_bytes
    JSON.generate(value).bytesize
  rescue JSON::GeneratorError, TypeError
    MAX_VALUE_BYTES + 1
  end

  private

  def validate_storage_limits
    if value_bytes > MAX_VALUE_BYTES
      errors.add(:value, 'is too large')
      return
    end

    return if account.nil?

    account_items = account.misskey_registry_items
    errors.add(:base, 'registry item limit exceeded') if new_record? && account_items.count >= MAX_ITEMS

    scope_items = account_items.where(domain: domain, scope: scope).where.not(id: id)
    errors.add(:base, 'registry scope item limit exceeded') if new_record? && scope_items.count >= MAX_SCOPE_ITEMS
    validate_byte_quota(scope_items, MAX_SCOPE_BYTES, 'registry scope storage limit exceeded')
    validate_byte_quota(account_items.where.not(id: id), MAX_ACCOUNT_BYTES, 'registry account storage limit exceeded')
  end

  def validate_byte_quota(other_items, limit, message)
    other_bytes = other_items.sum(Arel.sql('octet_length(misskey_registry_items.value::text)')).to_i
    projected_bytes = other_bytes + value_bytes
    return if projected_bytes <= limit

    stored_bytes = persisted? ? self.class.where(id: id).pick(Arel.sql('octet_length(misskey_registry_items.value::text)')).to_i : 0
    return if projected_bytes < other_bytes + stored_bytes

    errors.add(:value, message)
  end
end
