# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::ChatFederation::MediaToken do
  let(:media) { Fabricate(:media_attachment, status: nil) }

  describe '.valid?' do
    it 'refuses anything that is not a string' do
      [nil, '', ['forged'], { 'a' => 'b' }, ActionController::Parameters.new('a' => 'b')].each do |value|
        expect(described_class.valid?(value, media)).to be(false)
      end
    end
  end
end
