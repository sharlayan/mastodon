# frozen_string_literal: true

require 'rails_helper'

RSpec.describe REST::AvatarDecorationSerializer do
  subject { serialized_record_json(decoration, described_class) }

  let(:decoration) { Fabricate(:avatar_decoration, name: 'sparkle', description: 'A sparkly frame') }

  it 'returns expected attributes' do
    expect(subject).to include(
      'id' => decoration.id.to_s,
      'name' => 'sparkle',
      'description' => 'A sparkly frame'
    )
    expect(subject).to have_key('url')
    expect(subject).to have_key('static_url')
  end
end
