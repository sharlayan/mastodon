# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ReactionQuietHours do
  let(:user) { Fabricate(:user, time_zone: 'Asia/Seoul') }

  def configure(enabled: true, start: '23:00', finish: '07:00')
    user.settings.update(reaction_quiet_hours: enabled, reaction_quiet_hours_start: start, reaction_quiet_hours_end: finish)
    user.save!
  end

  def at_seoul(time)
    Time.find_zone!('Asia/Seoul').parse("2026-11-25 #{time}")
  end

  describe '.active?' do
    it 'follows the user time zone and wraps around midnight' do
      configure

      expect(described_class.active?(user, at_seoul('23:00'))).to be true
      expect(described_class.active?(user, at_seoul('03:30'))).to be true
      expect(described_class.active?(user, at_seoul('06:59'))).to be true
      expect(described_class.active?(user, at_seoul('07:00'))).to be false
      expect(described_class.active?(user, at_seoul('22:59'))).to be false
      expect(described_class.active?(user, at_seoul('23:00').utc)).to be true
    end

    it 'handles same-day windows, all-day windows and the disabled toggle' do
      configure(start: '09:00', finish: '18:30')

      expect(described_class.active?(user, at_seoul('09:00'))).to be true
      expect(described_class.active?(user, at_seoul('18:29'))).to be true
      expect(described_class.active?(user, at_seoul('18:30'))).to be false
      expect(described_class.active?(user, at_seoul('08:59'))).to be false

      configure(start: '12:00', finish: '12:00')
      expect(described_class.active?(user, at_seoul('00:00'))).to be true

      configure(enabled: false)
      expect(described_class.active?(user, at_seoul('23:30'))).to be false
      expect(described_class.active?(nil, at_seoul('23:30'))).to be false
    end

    it 'rejects times outside the selectable list' do
      expect { user.settings['reaction_quiet_hours_start'] = '23:15' }.to raise_error(ArgumentError)
    end
  end

  describe '.blocks?' do
    it 'applies only to other accounts reacting to a local account in quiet hours' do
      configure
      reactor = Fabricate(:account)
      remote_author = Fabricate(:account, domain: 'example.com')

      expect(described_class.blocks?(user.account, reactor, at_seoul('01:00'))).to be true
      expect(described_class.blocks?(user.account, user.account, at_seoul('01:00'))).to be false
      expect(described_class.blocks?(user.account, reactor, at_seoul('12:00'))).to be false
      expect(described_class.blocks?(remote_author, reactor, at_seoul('01:00'))).to be false
    end
  end
end
