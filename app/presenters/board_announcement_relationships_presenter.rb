# frozen_string_literal: true

class BoardAnnouncementRelationshipsPresenter
  attr_reader :reaction_groups_map

  def initialize(announcements, current_account = nil)
    @reaction_groups_map = BoardAnnouncement.reaction_groups_map(announcements.map(&:id), current_account)
  end
end
