# frozen_string_literal: true

module SharlayanCapabilitiesHelper
  def capabilities_for_nodeinfo
    InstanceMetadata.features_to_wire(InstanceMetadata.advertised_features)
  end
end
