# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Settings::FlavoursController do
  let(:user) { Fabricate(:user) }

  around do |example|
    ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') { example.run }
  end

  before do
    sign_in user, scope: :user
    allow(Themes.instance).to receive(:flavours).and_return(%w(glitch schnozzberry))
    allow(Themes.instance).to receive(:skins_for).with('schnozzberry').and_return(%w(wallpaper))
  end

  describe 'PUT #update' do
    context 'when roleplay mode is enabled' do
      around do |example|
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
      end

      before do
        allow(Themes.instance).to receive(:skins_for).with('glitch').and_return(%w(default))
      end

      it 'forces the glitch flavour' do
        put :update, params: { flavour: 'schnozzberry' }

        expect(user.reload.setting_flavour).to eq('glitch')
      end
    end

    describe 'without a user[setting_skin] parameter' do
      it 'sets the selected flavour' do
        put :update, params: { flavour: 'schnozzberry' }

        user.reload

        expect(user.setting_flavour).to eq 'schnozzberry'
        expect(user.setting_skin).to eq 'wallpaper'
      end
    end

    describe 'with a user[setting_skin] parameter' do
      before do
        put :update, params: { flavour: 'schnozzberry', user: { setting_skin: 'wallpaper' } }

        user.reload
      end

      it 'sets the selected flavour' do
        expect(user.setting_flavour).to eq 'schnozzberry'
      end

      it 'sets the selected skin' do
        expect(user.setting_skin).to eq 'wallpaper'
      end
    end

    context 'with an unknown flavour' do
      it 'does not change the selected theme' do
        put :update, params: { flavour: 'unknown' }

        expect(user.reload.setting_flavour).to eq 'glitch'
      end
    end

    context 'with an unknown skin' do
      it 'does not change the selected theme' do
        put :update, params: { flavour: 'schnozzberry', user: { setting_skin: 'unknown' } }

        expect(user.reload.setting_flavour).to eq 'glitch'
        expect(user.setting_skin).to eq 'default'
      end
    end
  end
end
