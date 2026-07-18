# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InitialStateSerializer do
  it 'adds signed-in Sharlayan preferences and mute snapshots' do
    user = Fabricate(:user)
    presenter = InitialStatePresenter.new(current_account: user.account, settings: {})
    meta = described_class.new(presenter).meta

    expect(meta).to include(
      visible_reactions: 6,
      reactions_enabled: Setting.reactions_enabled,
      mfm_fold_mode: 'sensitive',
      avatar_decoration_shape: 'none',
      custom_emoji_mutes: [],
      reaction_mutes: []
    )
  end

  it 'adds server feature gates for guests without signed-in snapshots' do
    meta = described_class.new(InitialStatePresenter.new(settings: {})).meta

    expect(meta).to include(
      circles_enabled: Setting.circles_enabled,
      clips_enabled: Setting.clips_enabled,
      pages_enabled: Setting.pages_enabled,
      drive_enabled: Setting.drive_enabled,
      roleplay_mode: RoleplayModeHelper.roleplay_mode?
    )
    expect(meta).to_not include(:custom_emoji_mutes, :reaction_mutes)
  end

  it 'exposes the reaction limit as a top-level attribute' do
    serializer = described_class.new(InitialStatePresenter.new(settings: {}))

    expect(serializer.max_reactions).to eq(StatusReactionValidator::LIMIT)
  end
end
