# frozen_string_literal: true

module LowResourceFeatures
  module_function

  def enabled?(name, default:)
    value = ENV.fetch(name, nil)
    value.nil? ? default : value != 'false'
  end
  private_class_method :enabled?

  TRENDS_PROCESSING_ENABLED = enabled?('TRENDS_PROCESSING_ENABLED', default: true)

  NONESSENTIAL_SCHEDULERS_ENABLED = enabled?('NONESSENTIAL_SCHEDULERS_ENABLED', default: true)

  FOLLOW_RECOMMENDATIONS_REFRESH_ENABLED = enabled?(
    'FOLLOW_RECOMMENDATIONS_REFRESH_ENABLED',
    default: NONESSENTIAL_SCHEDULERS_ENABLED
  )

  INSTANCE_REFRESH_ENABLED = enabled?(
    'INSTANCE_REFRESH_ENABLED',
    default: NONESSENTIAL_SCHEDULERS_ENABLED
  )

  def trends_processing_enabled?
    TRENDS_PROCESSING_ENABLED
  end

  def follow_recommendations_refresh_enabled?
    FOLLOW_RECOMMENDATIONS_REFRESH_ENABLED
  end

  def instance_refresh_enabled?
    INSTANCE_REFRESH_ENABLED
  end
end
