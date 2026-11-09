# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClipFavourite do
  describe '.visible_to' do
    let(:viewer) { Fabricate(:account) }
    let(:owner) { Fabricate(:account) }
    let(:clip) { Fabricate(:clip, account: owner, public: true) }
    let!(:favourite) { described_class.create!(account: viewer, clip: clip) }

    it 'includes public clips of other accounts' do
      expect(described_class.visible_to(viewer)).to include(favourite)
    end

    it 'excludes clips whose owner blocks the viewer' do
      owner.block!(viewer)

      expect(described_class.visible_to(viewer)).to_not include(favourite)
    end

    it 'keeps clips when only the viewer blocks the owner' do
      viewer.block!(owner)

      expect(described_class.visible_to(viewer)).to include(favourite)
    end

    it 'excludes private clips of other accounts' do
      clip.update!(public: false)

      expect(described_class.visible_to(viewer)).to_not include(favourite)
    end
  end
end
