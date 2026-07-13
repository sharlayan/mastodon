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
