# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe Rake::Task do
  describe 'roleplay:hide_period' do
    subject { described_class['roleplay:hide_period'] }

    let!(:status) { Fabricate(:status, account: Fabricate(:account, domain: nil)) }

    before do
      Rails.application.load_tasks unless described_class.tasks.any?
      subject.reenable
      Setting.soft_hide_deletion = true
    end

    around do |example|
      ClimateControl.modify(OC_ROLEPLAY_OPTION: 'true', BEFORE: before_value, AFTER: after_value) { example.run }
    end

    context 'when AFTER cannot be parsed' do
      let(:before_value) { 1.day.from_now.iso8601 }
      let(:after_value) { 'not-a-date' }

      it 'aborts without hiding statuses' do
        expect { subject.invoke }.to raise_error(SystemExit).and output(/AFTER/).to_stderr
        expect(status.reload.rp_hidden?).to be false
      end
    end

    context 'when BEFORE cannot be parsed' do
      let(:before_value) { 'not-a-date' }
      let(:after_value) { nil }

      it 'aborts without hiding statuses' do
        expect { subject.invoke }.to raise_error(SystemExit).and output(/BEFORE/).to_stderr
        expect(status.reload.rp_hidden?).to be false
      end
    end

    context 'when both bounds are valid' do
      let(:before_value) { 1.day.from_now.iso8601 }
      let(:after_value) { 1.day.ago.iso8601 }

      it 'hides statuses in the period' do
        expect { subject.invoke }.to output(/newly hidden 1/).to_stdout
        expect(Status.with_rp_hidden.find(status.id).rp_hidden?).to be true
      end
    end
  end
end
