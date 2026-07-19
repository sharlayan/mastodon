# frozen_string_literal: true

%w(
  /antennas/(*any)
  /board_announcements
  /circles/(*any)
  /clips/(*any)
  /conversations/(*any)
  /custom_emoji_mutes
  /drive
  /pages/(*any)
  /reaction_mutes
  /reactions
).each { |path| get path, to: 'home#index' }
