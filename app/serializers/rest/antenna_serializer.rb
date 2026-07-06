# frozen_string_literal: true

class REST::AntennaSerializer < ActiveModel::Serializer
  attributes :id, :title, :last_status_id,
             :available, :with_media_only, :ignore_reblog,
             :any_keywords, :any_accounts, :any_domains, :any_tags,
             :keywords, :exclude_keywords,
             :accounts, :exclude_accounts,
             :domains, :exclude_domains,
             :tags, :exclude_tags

  def id
    object.id.to_s
  end

  def last_status_id
    object.last_status_id
  end

  def keywords
    object.keywords
  end

  def exclude_keywords
    object.exclude_keywords
  end

  def accounts
    object.antenna_accounts.includes_only.pluck(:account_id).map(&:to_s)
  end

  def exclude_accounts
    object.exclude_accounts.map(&:to_s)
  end

  def domains
    object.antenna_domains.includes_only.pluck(:name)
  end

  def exclude_domains
    object.exclude_domains
  end

  def tags
    object.tags.merge(AntennaTag.includes_only).pluck(:name)
  end

  def exclude_tags
    Tag.where(id: object.exclude_tags).pluck(:name)
  end
end
