# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sharlayan::RegistrationRejectionPatterns do
  it 'matches literal substrings and opt-in regular expressions while ignoring blank lines' do
    expect(described_class.match?('spam+123@example.com', "\r\n spam+ \r\n")).to be true
    expect(described_class.match?('spam123@example.com', 'spam+')).to be false
    expect(described_class.match?('Spam+123@example.com', 'spam+')).to be false
    expect(described_class.match?('Bot123', '?\A(?i:bot)\d+\z')).to be true
    expect(described_class.match?('realbot123', '?\A(?i:bot)\d+\z')).to be false
    expect(described_class.match?('alice', "\n\r\n")).to be false
    expect(described_class.match?(nil, '?.*')).to be false
  end

  it 'validates syntax and configuration limits without letting invalid stored expressions break registration' do
    expect(described_class.valid?("literal\r\n?\\Auser\\d+\\z")).to be true
    expect(described_class.valid?(nil)).to be true
    expect(described_class.valid?('')).to be true
    expect(described_class.valid?('?[')).to be false
    expect(described_class.valid?('?')).to be false
    expect(described_class.valid?('a' * (described_class::MAX_LENGTH + 1))).to be false
    expect(described_class.valid?("a\n" * (described_class::MAX_PATTERNS + 1))).to be false
    expect(described_class.match?('alice', "?[\nalice")).to be true
  end

  it 'rejects a match that exceeds its execution limit' do
    expression = Regexp.new('test', timeout: described_class::MATCH_TIMEOUT)
    allow(Regexp).to receive(:new).with('test', timeout: described_class::MATCH_TIMEOUT).and_return(expression)
    allow(expression).to receive(:match?).and_raise(Regexp::TimeoutError)

    expect(described_class.match?('test', '?test')).to be true
  end
end
