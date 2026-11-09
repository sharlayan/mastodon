# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserSettings do
  subject(:settings) { described_class.new({}) }

  it 'provides privacy-safe and Drive defaults' do
    expect(settings[:show_online_status]).to be false
    expect(settings[:default_quote_policy]).to eq('nobody')
    expect(settings[:default_reaction_acceptance]).to be_nil
    expect(settings[:norss]).to be false
    expect(settings[:enable_rss]).to be true
    expect(settings[:visible_reactions]).to eq(6)
    expect(settings[:drive_keep_original_filename]).to be true
    expect(settings[:drive_upload_original_image]).to be true
    expect(settings[:inline_compose_tabs]).to eq('[]')
  end

  it 'uses the instance RSS setting until a user changes it and persists the enable_rss inverse alias as norss' do
    Setting.norss = true

    expect(settings[:norss]).to be true
    expect(settings[:enable_rss]).to be false

    Setting.norss = false
    changed = described_class.new({})
    changed[:enable_rss] = false

    expect(changed[:norss]).to be true
    expect(changed.as_json).to include(norss: true)
  ensure
    Setting.norss = false
  end

  it 'registers namespaced MFM, avatar decoration, and notification settings' do
    expect(settings[:'web.mfm_fold_mode']).to eq('sensitive')
    expect(settings[:'web.pages_view']).to eq('list')
    expect(settings[:'web.pages_blog_list_position']).to eq('left')
    expect(settings[:'web.ignore_others_pages_view']).to be false
    expect(settings[:'avatar_decorations.shape']).to eq('none')
    expect(settings[:'cat.show']).to be true
    expect(settings[:'cat.show_speak']).to be true
    expect(settings[:'cat.show_federated']).to be true
    expect(settings[:'notification_emails.reaction']).to be false
  end

  it 'defaults My archive to community mode while preserving an explicit preference' do
    saved_settings = described_class.new('web.use_my_archive': false)

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
      expect(settings[:'web.use_my_archive']).to be false
    end

    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') do
      expect(settings[:'web.use_my_archive']).to be true
      expect(saved_settings[:'web.use_my_archive']).to be false
    end
  end

  it 'rejects values outside Sharlayan setting allowlists and the migrated instance badge key' do
    expect { settings[:'web.mfm_fold_mode'] = 'unknown' }.to raise_error(ArgumentError)
    expect { settings[:'web.pages_view'] = 'magazine' }.to raise_error(ArgumentError)
    expect { settings[:'web.pages_blog_list_position'] = 'top' }.to raise_error(ArgumentError)
    expect { settings[:default_reaction_acceptance] = 'customOnly' }.to raise_error(ArgumentError)
    expect { settings[:'avatar_decorations.shape'] = 'triangle' }.to raise_error(ArgumentError)
    expect { settings[:'web.show_instance_info'] }.to raise_error(UserSettings::KeyError)
  end
end
