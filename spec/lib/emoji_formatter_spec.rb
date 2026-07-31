# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmojiFormatter do
  let!(:emoji) { Fabricate(:custom_emoji, shortcode: 'coolcat') }

  def preformat_text(str)
    TextFormatter.new(str).to_s
  end

  describe '#to_s' do
    subject { described_class.new(text, emojis).to_s }

    let(:emojis) { [emoji] }

    context 'when given text that is not marked as html-safe' do
      let(:text) { 'Foo' }

      it 'raises an argument error' do
        expect { subject }.to raise_error ArgumentError
      end
    end

    context 'when given text with an emoji shortcode at the start' do
      let(:text) { preformat_text(':coolcat: Beep boop') }

      it 'converts the shortcode to an image tag' do
        expect(subject).to include('<img rel="emoji" draggable="false" width="16" height="16" class="emojione custom-emoji" alt=":coolcat:"')
      end
    end

    context 'when given text with an emoji shortcode in the middle' do
      let(:text) { preformat_text('Beep :coolcat: boop') }

      it 'converts the shortcode to an image tag' do
        expect(subject).to include('Beep <img rel="emoji" draggable="false" width="16" height="16" class="emojione custom-emoji" alt=":coolcat:"')
      end
    end

    context 'when given text with concatenated emoji shortcodes' do
      let(:text) { preformat_text(':coolcat::coolcat:') }

      it 'converts both shortcodes to image tags' do
        expect(subject.scan('<img rel="emoji"').size).to eq(2)
      end
    end

    context 'when given text with an emoji shortcode at the end' do
      let(:text) { preformat_text('Beep boop :coolcat:') }

      it 'converts the shortcode to an image tag' do
        expect(subject).to include('boop <img rel="emoji" draggable="false" width="16" height="16" class="emojione custom-emoji" alt=":coolcat:"')
      end
    end

    context 'when a shortcode directly follows a word character' do
      let(:text) { preformat_text('Name:coolcat:') }

      it 'does not convert the shortcode by default' do
        expect(subject).to_not include('<img rel="emoji"')
      end

      it 'converts the shortcode when unbounded shortcodes are allowed' do
        result = described_class.new(text, emojis, allow_unbounded_shortcodes: true).to_s

        expect(result).to include('Name<img rel="emoji"')
      end
    end
  end
end
