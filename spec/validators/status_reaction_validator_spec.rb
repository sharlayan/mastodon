# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusReactionValidator do
  let(:status) { Fabricate(:status) }

  describe '#validate' do
    it 'adds error when not a valid unicode emoji' do
      reaction = status.status_reactions.build(name: 'F', account: Fabricate(:account))
      subject.validate(reaction)
      expect(reaction.errors).to_not be_empty
    end

    it 'does not add error when non-unicode emoji is a custom emoji' do
      custom_emoji = Fabricate(:custom_emoji)
      reaction = status.status_reactions.build(name: custom_emoji.shortcode, custom_emoji_id: custom_emoji.id, account: Fabricate(:account))
      subject.validate(reaction)
      expect(reaction.errors).to be_empty
    end

    it 'adds error when reaction limit count has already been reached' do
      stub_const 'StatusReactionValidator::LIMIT', 2
      account = Fabricate(:account)
      %w(🐘 ❤️).each do |name|
        status.status_reactions.create!(name: name, account: account)
      end

      reaction = status.status_reactions.build(name: '😘', account: account)
      subject.validate(reaction)
      expect(reaction.errors).to_not be_empty
    end

    it 'does not add error when new reaction is part of the existing ones' do
      stub_const 'StatusReactionValidator::LIMIT', 2
      account = Fabricate(:account)
      %w(🐘 ❤️).each do |name|
        status.status_reactions.create!(name: name, account: account)
      end

      reaction = status.status_reactions.build(name: '🐘', account: account)
      subject.validate(reaction)
      expect(reaction.errors).to be_empty
    end
  end
end
