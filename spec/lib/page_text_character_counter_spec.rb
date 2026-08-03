# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PageTextCharacterCounter do
  it 'counts summary, section headings, and visible block text without formatting or whitespace' do
    count = described_class.call(
      summary: '요 약',
      content: [
        {
          type: 'section',
          title: '섹션 제목',
          children: [
            { type: 'text', text: '$[x2 hello] **bold** [label](https://example.com)' },
            { type: 'text', format: 'markdown', text: "# Heading\n\n**bold text**" },
          ],
        },
        { type: 'image', fileId: nil },
      ]
    )

    expect(count).to eq(35)
  end
end
