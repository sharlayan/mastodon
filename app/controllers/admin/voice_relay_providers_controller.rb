# frozen_string_literal: true

class Admin::VoiceRelayProvidersController < Admin::BaseController
  CALLS_LIMIT = 100

  before_action :set_provider, except: [:index, :new, :create]

  def index
    authorize :voice_relay_provider, :index?

    @providers = VoiceRelayProvider.order(:id)
    @calls = VoiceCallAllocation.unfinished.includes(:voice_relay_provider, :chat_conversation).order(updated_at: :desc).limit(CALLS_LIMIT)
    @local_origin = local_origin
  end

  def new
    authorize :voice_relay_provider, :create?

    @provider = VoiceRelayProvider.new
  end

  def edit
    authorize :voice_relay_provider, :update?
  end

  def create
    authorize :voice_relay_provider, :create?

    @provider = VoiceRelayProvider.new(resource_params)

    if @provider.save
      log_action :create, @provider
      redirect_to admin_voice_relay_providers_path, notice: I18n.t('admin.voice_relay_providers.created_msg')
    else
      render :new
    end
  end

  def update
    authorize :voice_relay_provider, :update?

    if @provider.update(resource_params)
      log_action :update, @provider
      redirect_to admin_voice_relay_providers_path, notice: I18n.t('admin.voice_relay_providers.updated_msg')
    else
      render :edit
    end
  end

  def destroy
    authorize :voice_relay_provider, :destroy?

    if @provider.destroy
      log_action :destroy, @provider
      redirect_to admin_voice_relay_providers_path, notice: I18n.t('admin.voice_relay_providers.destroyed_msg')
    else
      redirect_to admin_voice_relay_providers_path, alert: @provider.errors.full_messages.to_sentence
    end
  end

  def check
    authorize :voice_relay_provider, :update?

    capacity = @provider.check!

    if capacity['enabled']
      redirect_to admin_voice_relay_providers_path, notice: I18n.t('admin.voice_relay_providers.check_succeeded_msg')
    else
      redirect_to admin_voice_relay_providers_path, alert: I18n.t('admin.voice_relay_providers.check_disabled_msg')
    end
  rescue Sharlayan::VoiceRelay::Error => e
    redirect_to admin_voice_relay_providers_path, alert: I18n.t('admin.voice_relay_providers.check_failed_msg', code: e.code)
  end

  def enable
    authorize :voice_relay_provider, :update?

    @provider.update!(enabled: true)
    log_action :enable, @provider
    redirect_to admin_voice_relay_providers_path
  end

  def disable
    authorize :voice_relay_provider, :update?

    @provider.update!(enabled: false)
    log_action :disable, @provider
    redirect_to admin_voice_relay_providers_path
  end

  private

  def set_provider
    @provider = VoiceRelayProvider.find(params[:id])
  end

  def local_origin
    Sharlayan::VoiceRelay::Origin.local
  rescue Sharlayan::VoiceRelay::Error
    nil
  end

  def resource_params
    params.expect(voice_relay_provider: [:origin, :secret])
  end
end
