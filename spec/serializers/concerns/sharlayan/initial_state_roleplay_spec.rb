# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::InitialStateRoleplay do
  let(:serializer_class) do
    Class.new do
      include Sharlayan::InitialStateRoleplay

      attr_reader :object

      def initialize(current_account:, user:, owner_viewer:)
        @object = Struct.new(:current_account).new(current_account)
        @user = user
        @owner_viewer = owner_viewer
      end

      private

      def object_account_user
        @user
      end

      def admin_timeline_owner_viewer?
        @owner_viewer
      end
    end
  end

  let(:user) { instance_double(User) }
  let(:serializer) { serializer_class.new(current_account: :account, user:, owner_viewer: true) }

  it 'preserves develop defaults when roleplay mode is disabled' do
    allow(RoleplayModeHelper).to receive(:roleplay_mode?).and_return(false)
    store = { antenna_enabled: true, mfm_enabled: false, show_avatar_decorations: false }

    expect(serializer.apply_sharlayan_roleplay_meta!(store)).to eq(
      antenna_enabled: true,
      mfm_enabled: false,
      show_avatar_decorations: false,
      roleplay_mode: false
    )
  end

  it 'applies community overrides only in roleplay mode' do
    allow(RoleplayModeHelper).to receive(:roleplay_mode?).and_return(true)
    allow(Setting).to receive(:[]).and_wrap_original do |original, key|
      %w(force_mfm_enabled force_avatar_decorations force_round_avatar soft_hide_deletion).include?(key) || original.call(key)
    end
    store = { antenna_enabled: true, mfm_enabled: false, show_avatar_decorations: false }

    expect(serializer.apply_sharlayan_roleplay_meta!(store)).to eq(
      antenna_enabled: false,
      mfm_enabled: true,
      show_avatar_decorations: true,
      roleplay_mode: true,
      force_round_avatar: true,
      admin_timeline_owner_viewer: true,
      soft_hide_deletion: true
    )
  end
end
