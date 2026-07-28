# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClipStatus do
  describe 'clip size validation' do
    let(:clip) { Fabricate(:clip) }

    before { stub_const('Clip::STATUSES_LIMIT', 1) }

    it 'rejects a new status once the clip is full' do
      clip.clip_statuses.create!(status: Fabricate(:status))
      extra = clip.clip_statuses.build(status: Fabricate(:status))

      expect(extra).to_not be_valid
      expect(extra.errors[:base]).to contain_exactly(I18n.t('clips.errors.statuses_limit', limit: 1))
    end
  end
end
