# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DriveFolder do
  let(:account) { Fabricate(:account) }

  describe 'parent ownership' do
    it 'rejects a parent owned by another account' do
      parent = described_class.create!(account: Fabricate(:account), name: 'Foreign')
      folder = described_class.new(account: account, name: 'Local', parent: parent)

      expect(folder).to_not be_valid
      expect(folder.errors.of_kind?(:parent_id, :invalid)).to be true
    end
  end

  describe 'folder hierarchy' do
    it 'rejects moving a folder below its descendant' do
      root = described_class.create!(account: account, name: 'Root')
      child = described_class.create!(account: account, name: 'Child', parent: root)
      grandchild = described_class.create!(account: account, name: 'Grandchild', parent: child)

      root.parent = grandchild

      expect(root).to_not be_valid
      expect(root.errors.of_kind?(:parent_id, :invalid)).to be true
    end
  end
end
