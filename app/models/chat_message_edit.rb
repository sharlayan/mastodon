# frozen_string_literal: true

# == Schema Information
#
# Table name: chat_message_edits
#
#  id              :bigint(8)        not null, primary key
#  text            :text
#  created_at      :datetime         not null
#  chat_message_id :bigint(8)        not null
#
class ChatMessageEdit < ApplicationRecord
  belongs_to :chat_message, inverse_of: :edits
end
