# frozen_string_literal: true

class Sharlayan::FederationUniverse
  MAX_EDGES = 250
  INTERACTIONS_SQL = '(reblogs_count + replies_count + quotes_count) DESC, source_domain ASC NULLS FIRST, target_domain ASC'

  def as_json
    edges = strongest_edges
    domains = edges.flat_map { |edge| [edge.source_domain, edge.target_domain] }.compact.uniq
    metadata = InstanceMetadata.where(domain: domains).index_by(&:domain)
    observed = MisskeyFederationInstanceStat.where(domain: domains).index_by(&:domain)
    unavailable = UnavailableDomain.where(domain: domains).pluck(:domain).to_set

    {
      local_domain: local_domain,
      generated_at: edges.filter_map(&:updated_at).max,
      nodes: node_domains(edges).map { |domain| node_json(domain, metadata[domain], observed[domain], unavailable.include?(domain)) },
      edges: edges.map { |edge| edge_json(edge) },
    }
  end

  private

  def strongest_edges
    FederationInstanceEdge
      .where.not(target_domain: nil)
      .order(Arel.sql(INTERACTIONS_SQL))
      .limit(MAX_EDGES)
      .to_a
  end

  def node_domains(edges)
    [nil, *edges.flat_map { |edge| [edge.source_domain, edge.target_domain] }].uniq
  end

  def node_json(domain, metadata, observed, gone)
    return local_node_json if domain.nil?

    {
      id: domain,
      domain: domain,
      name: metadata&.instance_name.presence || domain,
      software: metadata&.software,
      color: metadata&.theme_color_with_fallback,
      users: metadata&.local_users_count || observed&.users_count || 0,
      posts: metadata&.local_posts_count || observed&.notes_count || 0,
      gone: gone,
    }
  end

  def local_node_json
    presenter = InstancePresenter.new
    metadata = Sharlayan::LocalInstanceMetadata.to_h

    {
      id: local_domain,
      domain: local_domain,
      name: metadata[:instance_name],
      software: metadata[:software],
      color: metadata[:theme_color],
      users: presenter.user_count,
      posts: presenter.status_count,
      local: true,
      gone: false,
    }
  end

  def edge_json(edge)
    {
      source: edge.source_domain || local_domain,
      target: edge.target_domain,
      interactions: edge.interactions_count,
      reblogs: edge.reblogs_count,
      replies: edge.replies_count,
      quotes: edge.quotes_count,
    }
  end

  def local_domain
    @local_domain ||= Rails.configuration.x.local_domain
  end
end
