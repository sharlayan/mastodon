# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatMediaToken do
  let(:viewer) { Fabricate(:user).account }
  let(:other_viewer) { Fabricate(:user).account }
  let(:media) { Fabricate(:media_attachment, account: viewer, status: nil) }
  let(:other_media) { Fabricate(:media_attachment, account: viewer, status: nil) }

  before { travel_to Time.zone.at(((Time.now.to_i / 60) + 1) * 60) }

  describe 'staying the same so that a picture can be cached' do
    it 'is the same for one person and one attachment within a minute' do
      first = described_class.generate(media, viewer)

      travel 59.seconds

      expect(described_class.generate(media, viewer)).to eq(first)
    end

    it 'changes in the next minute' do
      first = described_class.generate(media, viewer)

      travel 60.seconds

      expect(described_class.generate(media, viewer)).to_not eq(first)
    end

    it 'differs between people' do
      expect(described_class.generate(media, viewer)).to_not eq(described_class.generate(media, other_viewer))
    end

    it 'differs between attachments' do
      expect(described_class.generate(media, viewer)).to_not eq(described_class.generate(other_media, viewer))
    end

    it 'differs for a Misskey client' do
      expect(described_class.generate(media, viewer)).to_not eq(described_class.generate(media, viewer, misskey: true))
    end
  end

  describe 'how long a token works' do
    it 'never works longer than ten minutes after it was given' do
      token = described_class.generate(media, viewer)

      travel 10.minutes

      expect(described_class.viewer(token, media)).to be_nil
    end

    it 'works for ten minutes when given at the start of a minute' do
      token = described_class.generate(media, viewer)

      travel 10.minutes - 1.second

      expect(described_class.viewer(token, media)).to eq(viewer)
    end

    it 'still works for nine minutes when given at the end of a minute' do
      travel 59.seconds
      token = described_class.generate(media, viewer)

      travel 9.minutes

      expect(described_class.viewer(token, media)).to eq(viewer)
    end
  end

  describe '.signed_for?' do
    let(:token) { described_class.generate(media, viewer) }

    it 'accepts a token for that attachment' do
      expect(described_class.signed_for?(token, media.id.to_s)).to be(true)
    end

    it 'refuses a token for another attachment' do
      expect(described_class.signed_for?(token, other_media.id.to_s)).to be(false)
    end

    it 'refuses an expired token' do
      token

      travel 10.minutes

      expect(described_class.signed_for?(token, media.id.to_s)).to be(false)
    end

    it 'refuses anything that was not signed here' do
      [nil, '', 'forged', "#{token.split('--').first}--#{'0' * 64}", ['forged'], { 'a' => 'b' }].each do |value|
        expect(described_class.signed_for?(value, media.id.to_s)).to be(false)
      end
    end

    it 'refuses a token that was signed for servers' do
      server_token = Sharlayan::ChatFederation::MediaToken.generate(media, domain: 'cherry.test')

      expect(described_class.signed_for?(server_token, media.id.to_s)).to be(false)
    end
  end

  describe '.viewer' do
    it 'refuses anything that is not a string' do
      [nil, ['forged'], { 'a' => 'b' }, ActionController::Parameters.new('a' => 'b')].each do |value|
        expect(described_class.viewer(value, media)).to be_nil
      end
    end
  end
end
