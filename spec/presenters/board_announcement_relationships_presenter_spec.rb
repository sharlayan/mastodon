# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BoardAnnouncementRelationshipsPresenter do
  let(:account)      { Fabricate(:account) }
  let(:other)        { Fabricate(:account) }
  let(:announcement) { BoardAnnouncement.create!(title: 'Notice', text: 'Body') }

  before do
    announcement.board_announcement_reactions.create!(account: account, name: '👍')
    announcement.board_announcement_reactions.create!(account: other, name: '👍')
  end

  it 'loads grouped reactions and the current account state in bulk' do
    reactions = described_class.new([announcement], account).reaction_groups_map.fetch(announcement.id)

    expect(reactions).to contain_exactly(have_attributes(name: '👍', count: 2, me: true))
  end
end
