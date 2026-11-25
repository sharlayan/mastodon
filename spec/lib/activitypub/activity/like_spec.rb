# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Like do
  let(:sender)    { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }
  let(:status)    { Fabricate(:status, account: recipient) }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Like',
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  describe '#perform' do
    subject { described_class.new(json, sender) }

    before do
      subject.perform
    end

    it 'creates a favourite from sender to status' do
      expect(sender.favourited?(status)).to be true
    end
  end

  describe '#perform with a non-string reaction content' do
    subject { described_class.new(json.merge(content: { evil: true }), sender) }

    it 'ignores the content and falls back to a favourite' do
      expect { subject.perform }.to_not raise_error
      expect(sender.favourited?(status)).to be true
      expect(StatusReaction.where(account: sender, status: status)).to_not exist
    end
  end

  describe '#perform with a unicode emoji reaction' do
    subject { described_class.new(json.merge(content: '😀'), sender) }

    it 'creates a reaction instead of a favourite' do
      subject.perform

      expect(StatusReaction.where(account: sender, status: status).pluck(:name)).to eq(['😀'])
      expect(sender.favourited?(status)).to be false
    end
  end

  describe '#perform with an emoji reaction during reaction quiet hours' do
    subject { described_class.new(json.merge(content: '😀'), sender) }

    before do
      recipient.user.update!(time_zone: 'Asia/Seoul')
      recipient.user.settings.update(reaction_quiet_hours: true, reaction_quiet_hours_start: '23:00', reaction_quiet_hours_end: '07:00')
      recipient.user.save!
    end

    it 'drops the reaction without turning it into a favourite' do
      travel_to(Time.find_zone!('Asia/Seoul').parse('2026-11-25 01:00')) { subject.perform }

      expect(StatusReaction.where(account: sender, status: status)).to_not exist
      expect(sender.favourited?(status)).to be false
    end
  end
end
