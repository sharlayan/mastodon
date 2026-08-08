import type { ApiFederationUniverse } from 'flavours/glitch/api/federation_universe';

import { buildUniverseLayout } from './layout';
import type { UniverseNode } from './layout';

const universe = (interactions: number): ApiFederationUniverse => ({
  local_domain: 'local.example',
  generated_at: null,
  nodes: [
    {
      id: 'local.example',
      domain: 'local.example',
      name: 'Local',
      software: 'mastodon',
      color: '#6364ff',
      users: 100,
      posts: 1_000,
      local: true,
      gone: false,
    },
    {
      id: 'remote.example',
      domain: 'remote.example',
      name: 'Remote',
      software: 'misskey',
      color: '#a1ca03',
      users: 10,
      posts: 100,
      gone: false,
    },
  ],
  edges: [
    {
      source: 'local.example',
      target: 'remote.example',
      interactions,
      reblogs: interactions,
      replies: 0,
      quotes: 0,
    },
  ],
});

const distanceFromOrigin = (interactions: number) => {
  const remote = buildUniverseLayout(universe(interactions)).find(
    (node) => node.id === 'remote.example',
  );

  return Math.hypot(remote?.x ?? 0, remote?.y ?? 0, remote?.z ?? 0);
};

describe('federation universe layout', () => {
  it('is deterministic for the same federation snapshot', () => {
    expect(buildUniverseLayout(universe(20))).toEqual(
      buildUniverseLayout(universe(20)),
    );
  });

  it('places servers with more interactions closer together', () => {
    expect(distanceFromOrigin(2_000)).toBeLessThan(distanceFromOrigin(2));
  });

  it('combines both directions into one relationship force', () => {
    const bidirectional = universe(1_000);
    const originalEdge = bidirectional.edges[0];
    if (!originalEdge) throw new Error('Expected the local relationship');

    bidirectional.edges[0] = {
      ...originalEdge,
      interactions: 400,
      reblogs: 400,
    };
    bidirectional.edges.push({
      source: 'remote.example',
      target: 'local.example',
      interactions: 600,
      reblogs: 600,
      replies: 0,
      quotes: 0,
    });

    expect(buildUniverseLayout(bidirectional)).toEqual(
      buildUniverseLayout(universe(1_000)),
    );
  });

  it('clusters strongly interacting instances ahead of unrelated ones', () => {
    const clustered = universe(5);
    clustered.nodes.push(
      ...['near-a.example', 'near-b.example', 'far.example'].map((domain) => ({
        id: domain,
        domain,
        name: domain,
        software: 'mastodon',
        color: '#6364ff',
        users: 10,
        posts: 100,
        gone: false,
      })),
    );
    clustered.edges.push(
      {
        source: 'near-a.example',
        target: 'near-b.example',
        interactions: 20_000,
        reblogs: 20_000,
        replies: 0,
        quotes: 0,
      },
      {
        source: 'near-a.example',
        target: 'far.example',
        interactions: 2,
        reblogs: 2,
        replies: 0,
        quotes: 0,
      },
    );

    const nodes = new Map(
      buildUniverseLayout(clustered).map((node) => [node.id, node]),
    );
    const nearA = nodes.get('near-a.example');
    const nearB = nodes.get('near-b.example');
    const far = nodes.get('far.example');
    const distance = (first?: UniverseNode, second?: UniverseNode) =>
      first && second
        ? Math.hypot(first.x - second.x, first.y - second.y, first.z - second.z)
        : Number.POSITIVE_INFINITY;

    expect(distance(nearA, nearB)).toBeLessThan(distance(nearA, far));
  });

  it('forms remote constellations instead of a local-server star', () => {
    const constellation = universe(5_000);
    constellation.nodes.push(
      ...['cluster-a.example', 'cluster-b.example', 'outsider.example'].map(
        (domain) => ({
          id: domain,
          domain,
          name: domain,
          software: 'mastodon',
          color: '#6364ff',
          users: 10,
          posts: 100,
          gone: false,
        }),
      ),
    );
    constellation.edges.push(
      ...constellation.nodes.slice(2).map((node) => ({
        source: 'local.example',
        target: node.id,
        interactions: 5_000,
        reblogs: 5_000,
        replies: 0,
        quotes: 0,
      })),
      {
        source: 'remote.example',
        target: 'cluster-a.example',
        interactions: 20_000,
        reblogs: 20_000,
        replies: 0,
        quotes: 0,
      },
      {
        source: 'cluster-a.example',
        target: 'cluster-b.example',
        interactions: 20_000,
        reblogs: 20_000,
        replies: 0,
        quotes: 0,
      },
    );

    const nodes = new Map(
      buildUniverseLayout(constellation).map((node) => [node.id, node]),
    );
    const remote = nodes.get('remote.example');
    const clusterA = nodes.get('cluster-a.example');
    const clusterB = nodes.get('cluster-b.example');
    const outsider = nodes.get('outsider.example');
    const distance = (first?: UniverseNode, second?: UniverseNode) =>
      first && second
        ? Math.hypot(first.x - second.x, first.y - second.y, first.z - second.z)
        : Number.POSITIVE_INFINITY;

    expect(distance(remote, clusterA)).toBeLessThan(distance(remote, outsider));
    expect(distance(clusterA, clusterB)).toBeLessThan(
      distance(clusterA, outsider),
    );
  });

  it('keeps dense constellation nodes separated in three dimensions', () => {
    const dense = universe(100);
    dense.nodes.push(
      ...Array.from({ length: 30 }, (_, index) => ({
        id: `remote-${index}.example`,
        domain: `remote-${index}.example`,
        name: `Remote ${index}`,
        software: 'mastodon',
        color: '#6364ff',
        users: 10,
        posts: 100,
        gone: false,
      })),
    );
    dense.edges.push(
      ...dense.nodes.slice(2).map((node, index) => ({
        source: 'local.example',
        target: node.id,
        interactions: 100 + index,
        reblogs: 100 + index,
        replies: 0,
        quotes: 0,
      })),
    );

    const nodes = buildUniverseLayout(dense);
    let minimumDistance = Number.POSITIVE_INFINITY;
    for (let first = 0; first < nodes.length; first += 1) {
      for (let second = first + 1; second < nodes.length; second += 1) {
        const a = nodes[first];
        const b = nodes[second];
        if (!a || !b) continue;
        minimumDistance = Math.min(
          minimumDistance,
          Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z),
        );
      }
    }

    expect(minimumDistance).toBeGreaterThan(700);
  });
});
