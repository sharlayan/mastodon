# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClipRelationshipsPresenter do
  subject(:presenter) { described_class.new([first_clip, second_clip], account.id) }

  let(:account)     { Fabricate(:account) }
  let(:other)       { Fabricate(:account) }
  let(:first_clip)  { Clip.create!(account: account, title: 'First') }
  let(:second_clip) { Clip.create!(account: account, title: 'Second') }

  before do
    first_clip.clip_statuses.create!(status: Fabricate(:status, account: account))
    first_clip.clip_statuses.create!(status: Fabricate(:status, account: account))
    first_clip.clip_favourites.create!(account: account)
    first_clip.clip_favourites.create!(account: other)
    second_clip.clip_favourites.create!(account: other)
  end

  it 'loads counts and the current account favourite state in bulk' do
    expect(presenter.statuses_count_map).to eq(first_clip.id => 2)
    expect(presenter.favourites_count_map).to eq(first_clip.id => 2, second_clip.id => 1)
    expect(presenter.favourited_map).to eq(first_clip.id => true)
  end
end
