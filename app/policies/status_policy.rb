# frozen_string_literal: true

class StatusPolicy < ApplicationPolicy
  include RoleplayModeHelper

  def show?
    return false if author.unavailable?
    return false if local_only? && (current_account.nil? || !current_account.local?)
    return rp_owner? if roleplay_mode? && rp_hidden?
    return true if roleplay_admin?

    if requires_mention?
      owned? || mention_exists?
    elsif private?
      owned? || following_author? || mention_exists?
    else
      current_account.nil? || (!author_blocking? && !author_blocking_domain?)
    end
  end

  def quote?
    !(roleplay_mode? && rp_hidden?) && show? && !blocking_author? && record.quote_policy_for_account(current_account) != :denied
  end

  def reblog?
    !(roleplay_mode? && rp_hidden?) && !requires_mention? && (!private? || owned?) && show? && !blocking_author?
  end

  def favourite?
    !(roleplay_mode? && rp_hidden?) && show? && !blocking_author?
  end

  def react?
    !(roleplay_mode? && rp_hidden?) && show? && !blocking_author?
  end

  def destroy?
    owned? || (roleplay_mode? && Setting.soft_hide_deletion && record.local? && rp_owner?)
  end

  def unreblog?
    owned?
  end

  def update?
    owned?
  end

  private

  def rp_hidden?
    return @rp_hidden if defined?(@rp_hidden)

    @rp_hidden = record.rp_hidden?
  end

  def requires_mention?
    record.direct_visibility? || record.limited_visibility?
  end

  def owned?
    author.id == current_account&.id
  end

  def private?
    record.private_visibility?
  end

  def mention_exists?
    return false if current_account.nil?

    if record.mentions.loaded?
      record.mentions.any? { |mention| mention.account_id == current_account.id }
    else
      record.mentions.exists?(account: current_account)
    end
  end

  def author_blocking_domain?
    return false if current_account.nil? || current_account.domain.nil?

    author.domain_blocking?(current_account.domain)
  end

  def blocking_author?
    return false if current_account.nil?

    current_account.blocking?(author)
  end

  def author_blocking?
    return false if current_account.nil?

    current_account.blocked_by?(author)
  end

  def following_author?
    return false if current_account.nil?

    current_account.following?(author)
  end

  def author
    record.account
  end

  def local_only?
    record.local_only?
  end

  def roleplay_admin?
    roleplay_mode? && role.administrator?
  end

  def rp_owner?
    return false unless roleplay_mode?
    return false if role.everyone?

    role.position == UserRole.assignable.maximum(:position)
  end
end
