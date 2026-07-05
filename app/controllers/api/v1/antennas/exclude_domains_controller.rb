# frozen_string_literal: true

class Api::V1::Antennas::ExcludeDomainsController < Api::BaseController
  include Api::AntennaFeatureConcern

  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    render json: { domains: @antenna.exclude_domains }
  end

  def create
    domains_list = (@antenna.exclude_domains + domains).uniq
    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_domains') if domains_list.size > Antenna::DOMAINS_PER_ANTENNA_LIMIT

    @antenna.update!(exclude_domains: domains_list)
    render json: { domains: @antenna.exclude_domains }
  end

  def destroy
    @antenna.update!(exclude_domains: @antenna.exclude_domains - domains)
    render json: { domains: @antenna.exclude_domains }
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def domains
    Array(params.permit(domains: [])[:domains]).filter_map { |domain| domain.to_s.strip.presence }
  end
end
