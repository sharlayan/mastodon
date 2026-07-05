# frozen_string_literal: true

class NodeInfo::DiscoverySerializer < ActiveModel::Serializer
  include RoutingHelper

  attribute :links

  def links
    [
      { rel: 'http://nodeinfo.diaspora.software/ns/schema/2.1', href: nodeinfo_2_1_schema_url },
      { rel: 'http://nodeinfo.diaspora.software/ns/schema/2.0', href: nodeinfo_schema_url },
    ]
  end
end
