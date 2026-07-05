# frozen_string_literal: true

class Api::V1::Antennas::ExcludeTagsController < Api::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    render json: load_tags, each_serializer: REST::TagSerializer
  end

  def create
    ids = (@antenna.exclude_tags + Tag.find_or_create_by_names(tag_names).map { |tag| tag.id.to_s }).uniq
    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_tags') if ids.size > Antenna::TAGS_PER_ANTENNA_LIMIT

    @antenna.update!(exclude_tags: ids)
    render json: load_tags, each_serializer: REST::TagSerializer
  end

  def destroy
    remove_ids = Tag.matching_name(tag_names).pluck(:id).map(&:to_s)
    @antenna.update!(exclude_tags: @antenna.exclude_tags - remove_ids)
    render json: load_tags, each_serializer: REST::TagSerializer
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def load_tags
    Tag.where(id: @antenna.exclude_tags)
  end

  def tag_names
    Array(params.permit(tags: [])[:tags]).filter_map { |tag| tag.to_s.strip.delete_prefix('#').presence }
  end
end
