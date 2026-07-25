# frozen_string_literal: true

# == Schema Information
#
# Table name: misskey_federation_instance_stats
#
#  id                 :bigint(8)        not null, primary key
#  domain             :string           not null
#  first_retrieved_at :datetime
#  followers_count    :integer          default(0), not null
#  following_count    :integer          default(0), not null
#  notes_count        :integer          default(0), not null
#  users_count        :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

class MisskeyFederationInstanceStat < ApplicationRecord
  validates :domain, presence: true, uniqueness: true

  def instance_metadata
    InstanceMetadata.cached_by_domain(domain)
  end
end
