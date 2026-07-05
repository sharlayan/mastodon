# frozen_string_literal: true

class REST::AntennaSerializer < ActiveModel::Serializer
  attributes :id, :title, :available, :with_media_only, :ignore_reblog,
             :any_keywords, :any_accounts, :any_domains, :any_tags,
             :keywords, :exclude_keywords,
             :accounts, :exclude_accounts,
             :domains, :exclude_domains,
             :tags, :exclude_tags

  def id
    object.id.to_s
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
    object.antenna_tags.includes_only.pluck(:tag_id).map(&:to_s)
  end

  def exclude_tags
    object.exclude_tags.map(&:to_s)
  end
end
