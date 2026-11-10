# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusReactionValidator do
  let(:status) { Fabricate(:status) }

  describe '#validate' do
    it 'adds an error for an invalid unicode emoji but not for a custom emoji' do
      custom_emoji = Fabricate(:custom_emoji)
      invalid = status.status_reactions.build(name: 'F', account: Fabricate(:account))
      custom = status.status_reactions.build(name: custom_emoji.shortcode, custom_emoji_id: custom_emoji.id, account: Fabricate(:account))

      subject.validate(invalid)
      subject.validate(custom)

      expect(invalid.errors).to_not be_empty
      expect(custom.errors).to be_empty
    end

    it 'adds an error once the reaction limit is reached unless the reaction is one of the existing ones' do
      stub_const 'StatusReactionValidator::LIMIT', 2
      account = Fabricate(:account)
      %w(🐘 ❤️).each do |name|
        status.status_reactions.create!(name: name, account: account)
      end

      new_reaction = status.status_reactions.build(name: '😘', account: account)
      existing_reaction = status.status_reactions.build(name: '🐘', account: account)
      subject.validate(new_reaction)
      subject.validate(existing_reaction)

      expect(new_reaction.errors).to_not be_empty
      expect(existing_reaction.errors).to be_empty
    end
  end
end
