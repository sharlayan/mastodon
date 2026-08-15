# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form::AdminSettings do
  describe 'Validations' do
    describe 'site_contact_username' do
      context 'with no accounts' do
        it { is_expected.to_not allow_value('Test').for(:site_contact_username) }
      end

      context 'with an account' do
        before { Fabricate(:account, username: 'Glorp') }

        it { is_expected.to_not allow_value('Test').for(:site_contact_username) }
        it { is_expected.to allow_value('Glorp').for(:site_contact_username) }
      end
    end
  end

  describe '#save' do
    it 'saves the RSS default setting as a boolean' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        Setting.norss = false

        expect { described_class.new(norss: '1').save }
          .to change(Setting, :norss).from(false).to(true)
      end
    end

    it 'saves the circles feature setting as a boolean' do
      expect { described_class.new(circles_enabled: '1').save }
        .to change(Setting, :circles_enabled).from(false).to(true)
    end

    it 'does not allow soft-hide deletion to be configured outside roleplay mode' do
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'false') do
        Setting.soft_hide_deletion = false

        expect { described_class.new(soft_hide_deletion: '1').save }
          .to not_change(Setting, :soft_hide_deletion)
      end
    end

    it 'saves roleplay avatar display overrides as booleans' do
      expect do
        described_class.new(
          force_avatar_decorations: '1',
          force_round_avatar: '1'
        ).save
      end.to change(Setting, :force_avatar_decorations).from(false).to(true)
        .and change(Setting, :force_round_avatar).from(false).to(true)
    end

    context 'when roleplay mode is enabled' do
      around do |example|
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
      end

      it 'returns authenticated access for the administrator form' do
        settings = described_class.new

        expect(settings.local_live_feed_access).to eq('authenticated')
        expect(settings.remote_live_feed_access).to eq('authenticated')
        expect(settings.local_topic_feed_access).to eq('authenticated')
        expect(settings.remote_topic_feed_access).to eq('authenticated')
        expect(settings.local_account_statuses_access).to eq('authenticated')
        expect(settings.local_status_page_access).to eq('authenticated')
        expect(settings.norss).to be(true)
        expect(settings.trends).to be(false)
        expect(settings.cat_enabled).to be(false)
        expect(settings.cat_federation_enabled).to be(false)
      end

      it 'saves the soft-hide deletion setting as a boolean' do
        expect { described_class.new(soft_hide_deletion: '1').save }
          .to change(Setting, :soft_hide_deletion).from(false).to(true)
      end

      it 'saves the local timeline control setting as a boolean' do
        Setting.roleplay_disable_local_timeline = true

        expect { described_class.new(roleplay_disable_local_timeline: '0').save }
          .to change(Setting, :roleplay_disable_local_timeline).from(true).to(false)
      end

      it 'persists forced settings instead of submitted values' do
        described_class.new(
          local_live_feed_access: 'public',
          remote_live_feed_access: 'public',
          local_topic_feed_access: 'public',
          remote_topic_feed_access: 'public',
          local_account_statuses_access: 'public',
          local_status_page_access: 'public',
          norss: '0',
          trends: '1',
          cat_enabled: '1',
          cat_federation_enabled: '1'
        ).save

        expect(Setting.local_live_feed_access).to eq('authenticated')
        expect(Setting.remote_live_feed_access).to eq('authenticated')
        expect(Setting.local_topic_feed_access).to eq('authenticated')
        expect(Setting.remote_topic_feed_access).to eq('authenticated')
        expect(Setting.local_account_statuses_access).to eq('authenticated')
        expect(Setting.local_status_page_access).to eq('authenticated')
        expect(Setting.norss).to be(true)
        expect(Setting.trends).to be(false)
        expect(Setting.cat_enabled).to be(false)
        expect(Setting.cat_federation_enabled).to be(false)
      end
    end

    it 'saves drive settings with their declared types' do
      expect { described_class.new(drive_enabled: '1', drive_quota: '2048').save }
        .to change(Setting, :drive_enabled).from(false).to(true)
        .and change(Setting, :drive_quota).from(500).to(2048)
    end

    it 'saves the status character limit as an integer' do
      expect { described_class.new(status_character_limit: '1000').save }
        .to change(Setting, :status_character_limit).from(500).to(1000)
    end

    it 'rejects a negative drive quota' do
      settings = described_class.new(drive_quota: '-1')

      expect(settings).to_not be_valid
      expect(settings.errors[:drive_quota]).to be_present
    end

    it 'saves the drive upload limits' do
      expect { described_class.new(drive_max_file_size: '32', drive_allowed_extensions: 'pdf, zip').save }
        .to change(Setting, :drive_max_file_size).from(20).to(32)
        .and change(Setting, :drive_allowed_extensions).from('').to('pdf, zip')
    end

    it 'rejects a drive file size limit of zero' do
      settings = described_class.new(drive_max_file_size: '0')

      expect(settings).to_not be_valid
      expect(settings.errors[:drive_max_file_size]).to be_present
    end

    it 'rejects allowed extensions that could be served as script or markup' do
      settings = described_class.new(drive_allowed_extensions: 'pdf, html, svg')

      expect(settings).to_not be_valid
      expect(settings.errors[:drive_allowed_extensions].join).to include('html', 'svg')
    end

    it 'accepts exact HTTPS origins for Misskey web sign-in' do
      settings = described_class.new(misskey_compat_signin_flow_allowed_origins: 'https://one.example, https://two.example:8443')

      expect(settings).to be_valid
    end

    it 'rejects unsafe or non-origin values for Misskey web sign-in' do
      settings = described_class.new(misskey_compat_signin_flow_allowed_origins: 'http://one.example https://two.example/path *.example')

      expect(settings).to_not be_valid
      expect(settings.errors[:misskey_compat_signin_flow_allowed_origins]).to be_present
    end

    describe 'updating digest values' do
      context 'when updating custom css to real value' do
        subject { described_class.new(custom_css: css) }

        let(:css) { 'body { color: red; }' }
        let(:digested) { Digest::SHA256.hexdigest(css) }

        it 'changes relevant digest value' do
          expect { subject.save }
            .to(change { Rails.cache.read(:setting_digest_custom_css) }.to(digested))
        end
      end

      context 'when updating custom css to empty value' do
        subject { described_class.new(custom_css: '') }

        before { Rails.cache.write(:setting_digest_custom_css, 'previous-value') }

        it 'changes relevant digest value' do
          expect { subject.save }
            .to(change { Rails.cache.read(:setting_digest_custom_css) }.to(be_blank))
        end
      end

      context 'when updating other fields' do
        subject { described_class.new(site_contact_email: 'test@example.host') }

        it 'does not update digests' do
          expect { subject.save }
            .to(not_change { Rails.cache.read(:setting_digest_custom_css) })
        end
      end
    end
  end

  describe '#persisted?' do
    it { is_expected.to be_persisted }
  end
end
