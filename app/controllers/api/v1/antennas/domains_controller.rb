# frozen_string_literal: true

class Api::V1::Antennas::DomainsController < Api::BaseController
  before_action -> { doorkeeper_authorize! :read, :'read:lists' }, only: [:show]
  before_action -> { doorkeeper_authorize! :write, :'write:lists' }, except: [:show]

  before_action :require_user!
  before_action :set_antenna

  def show
    render json: { domains: @antenna.antenna_domains.includes_only.pluck(:name) }
  end

  def create
    ApplicationRecord.transaction do
      domains.each do |domain|
        @antenna.antenna_domains.create_or_find_by!(name: domain) do |antenna_domain|
          antenna_domain.exclude = false
        end
      end
    end

    raise Mastodon::ValidationError, I18n.t('antennas.errors.too_many_domains') if @antenna.antenna_domains.includes_only.count > Antenna::DOMAINS_PER_ANTENNA_LIMIT

    render json: { domains: @antenna.antenna_domains.includes_only.pluck(:name) }
  end

  def destroy
    @antenna.antenna_domains.includes_only.where(name: domains).destroy_all
    render json: { domains: @antenna.antenna_domains.includes_only.pluck(:name) }
  end

  private

  def set_antenna
    @antenna = Antenna.where(account: current_account).find(params[:antenna_id])
  end

  def domains
    Array(params.permit(domains: [])[:domains]).filter_map { |domain| domain.to_s.strip.presence }
  end
end
