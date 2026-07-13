# frozen_string_literal: true

class Api::V1::BoardAnnouncements::ReactionsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :write, :'write:favourites' }
  before_action :require_user!
  before_action :check_enabled

  before_action :set_announcement
  before_action :set_reaction, except: :update

  def update
    @announcement.board_announcement_reactions.create!(account: current_account, name: params[:id])
    render_empty
  end

  def destroy
    @reaction.destroy!
    render_empty
  end

  private

  def check_enabled
    not_found unless Setting.board_announcements_enabled
  end

  def set_reaction
    @reaction = @announcement.board_announcement_reactions.where(account: current_account).find_by!(name: params[:id])
  end

  def set_announcement
    @announcement = BoardAnnouncement.published.for_account(current_account).find(params[:board_announcement_id])
  end
end
