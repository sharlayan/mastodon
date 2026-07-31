# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Parser::CustomEmojiParser do
  it 'reads the federated sensitive flag' do
    parser = described_class.new('name' => ':blob:', 'icon' => { 'url' => 'https://remote.example/blob.png' }, 'isSensitive' => true)

    expect(parser.sensitive).to be(true)
  end

  it 'distinguishes an omitted flag from an explicit false value' do
    omitted = described_class.new('name' => ':blob:')
    explicit = described_class.new('name' => ':blob:', 'isSensitive' => false)

    expect(omitted.sensitive).to be_nil
    expect(explicit.sensitive).to be(false)
  end
end
