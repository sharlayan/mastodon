# frozen_string_literal: true

module Sharlayan::Account::Interactions
  extend ActiveSupport::Concern

  included do
    has_many :domain_mutes, class_name: 'AccountDomainMute', dependent: :destroy
  end

  def mute_domain!(other_domain, hide_from_home: nil)
    hide_from_home = false if hide_from_home.nil?

    domain_mute = domain_mutes.create_with(hide_from_home: hide_from_home).find_or_initialize_by(domain: other_domain)
    domain_mute.save!
    domain_mute.update(hide_from_home: hide_from_home) if domain_mute.hide_from_home? != hide_from_home

    domain_mute
  end

  def unmute_domain!(other_domain)
    mute = domain_mutes.find_by(domain: normalized_domain(other_domain))
    mute&.destroy
  end

  def auto_accept_follow_from?(other_account)
    local? && !other_account.silenced? && user&.setting_auto_accept_followed && following?(other_account)
  end

  def reacted?(status, name = nil, custom_emoji = nil)
    if name.nil?
      status.proper.status_reactions.exists?(account: self)
    else
      status.proper.status_reactions.exists?(account: self, name: name, custom_emoji: custom_emoji)
    end
  end
end
