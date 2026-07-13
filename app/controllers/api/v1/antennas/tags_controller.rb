# frozen_string_literal: true

class Api::V1::Antennas::TagsController < Api::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    render json: @antenna.tags.merge(AntennaTag.includes_only), each_serializer: REST::TagSerializer
  end

  def create
    ApplicationRecord.transaction do
      validate_limit!

      tags_from_names.each do |tag|
        @antenna.antenna_tags.create_or_find_by!(tag_id: tag.id) do |antenna_tag|
          antenna_tag.exclude = false
        end
      end
    end

    render json: @antenna.tags.merge(AntennaTag.includes_only), each_serializer: REST::TagSerializer
  end

  def destroy
    tag_ids = Tag.matching_name(tag_names).pluck(:id)
    @antenna.antenna_tags.includes_only.where(tag_id: tag_ids).destroy_all
    render json: @antenna.tags.merge(AntennaTag.includes_only), each_serializer: REST::TagSerializer
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def tags_from_names
    Tag.find_or_create_by_names(tag_names)
  end

  def tag_names
    Array(params.permit(tags: [])[:tags]).filter_map { |tag| tag.to_s.strip.delete_prefix('#').presence }.uniq
  end

  def validate_limit!
    existing_names = @antenna.tags.merge(AntennaTag.includes_only).pluck(:name)
    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_tags') if (existing_names | tag_names).size > Antenna::TAGS_PER_ANTENNA_LIMIT
  end
end
