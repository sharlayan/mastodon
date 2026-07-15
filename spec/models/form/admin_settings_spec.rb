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
    it 'saves the circles feature setting as a boolean' do
      expect { described_class.new(circles_enabled: '1').save }
        .to change(Setting, :circles_enabled).from(false).to(true)
    end

    context 'when roleplay mode is enabled' do
      around do |example|
        ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true') { example.run }
      end

      before do
        Setting.force_local_only = false
        Setting.peers_api_enabled = true
      end

      after do
        Setting.force_local_only = false
        Setting.peers_api_enabled = true
      end

      it 'persists forced values instead of submitted values' do
        described_class.new(force_local_only: '0', peers_api_enabled: '1').save

        expect(Setting.force_local_only).to be(true)
        expect(Setting.peers_api_enabled).to be(false)
      end
    end

    it 'saves drive settings with their declared types' do
      expect { described_class.new(drive_enabled: '1', drive_quota: '2048').save }
        .to change(Setting, :drive_enabled).from(false).to(true)
        .and change(Setting, :drive_quota).from(500).to(2048)
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
