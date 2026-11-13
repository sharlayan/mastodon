# frozen_string_literal: true

class AddRevokedAtToVoiceRelayProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :voice_relay_providers, :revoked_at, :datetime
  end
end
