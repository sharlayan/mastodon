# frozen_string_literal: true

class Api::V1::Antennas::StatusesController < Api::BaseController
  include Api::AntennaFeatureConcern
  include Redisable

  before_action -> { doorkeeper_authorize! :write, :'write:lists' }
  before_action :require_user!
  before_action :set_antenna
  before_action :set_feed_status

  def destroy
    target_status = @feed_status.reblog || @feed_status
    FeedManager.instance.remove_status_from_antenna(@antenna, target_status)
    render_empty
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def set_feed_status
    feed_key = FeedManager.instance.key(:antenna, @antenna.id)
    return not_found unless redis.zscore(feed_key, params[:id])

    @feed_status = Status.find(params[:id])
  end
end
