# frozen_string_literal: true

class NodeInfo::AdapterTwoOne < ActiveModelSerializers::Adapter::Attributes
  def self.default_key_transform
    :unaltered
  end
end
