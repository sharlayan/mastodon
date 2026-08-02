# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserSettings do
  subject(:settings) { described_class.new({}) }

  it 'provides privacy-safe and Drive defaults' do
    expect(settings[:hide_online_status]).to be true
    expect(settings[:show_online_status]).to be false
    expect(settings[:default_quote_policy]).to eq('nobody')
    expect(settings[:default_reaction_acceptance]).to be_nil
    expect(settings[:visible_reactions]).to eq(6)
    expect(settings[:drive_keep_original_filename]).to be true
    expect(settings[:drive_upload_original_image]).to be true
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

  it 'rejects values outside Sharlayan setting allowlists' do
    expect { settings[:'web.mfm_fold_mode'] = 'unknown' }.to raise_error(ArgumentError)
    expect { settings[:'web.pages_view'] = 'magazine' }.to raise_error(ArgumentError)
    expect { settings[:'web.pages_blog_list_position'] = 'top' }.to raise_error(ArgumentError)
    expect { settings[:default_reaction_acceptance] = 'customOnly' }.to raise_error(ArgumentError)
    expect { settings[:'avatar_decorations.shape'] = 'triangle' }.to raise_error(ArgumentError)
  end

  it 'does not register the migrated instance badge preference as a server setting' do
    expect { settings[:'web.show_instance_info'] }.to raise_error(UserSettings::KeyError)
  end
end
