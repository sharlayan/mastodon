import type {
  ApiFederationUniverse,
  ApiFederationUniverseNode,
} from 'flavours/glitch/api/federation_universe';

export interface UniverseNode extends ApiFederationUniverseNode {
  x: number;
  y: number;
  z: number;
  radius: number;
  mass: number;
}

const WORLD_SCALE = 25;
const LAYOUT_ITERATIONS = 140;
const REPULSION_INTERVAL = 4;
const REPULSION_CELL_SIZE = 360;
const COLLISION_CELL_SIZE = 96;
const STRONG_INTERACTION_REFERENCE = Math.log1p(20_000);

interface LayoutEdge {
  source: UniverseNode;
  target: UniverseNode;
  interactions: number;
}

type PairCallback = (first: UniverseNode, second: UniverseNode) => void;

const cellKey = (x: number, y: number, z: number) => `${x}:${y}:${z}`;

const forEachNearbyPair = (
  nodes: UniverseNode[],
  cellSize: number,
  callback: PairCallback,
) => {
  const cells = new Map<string, { node: UniverseNode; index: number }[]>();

  for (const [index, node] of nodes.entries()) {
    const x = Math.floor(node.x / cellSize);
    const y = Math.floor(node.y / cellSize);
    const z = Math.floor(node.z / cellSize);
    const key = cellKey(x, y, z);
    const cell = cells.get(key) ?? [];
    cell.push({ node, index });
    cells.set(key, cell);
  }

  for (const [firstIndex, first] of nodes.entries()) {
    const x = Math.floor(first.x / cellSize);
    const y = Math.floor(first.y / cellSize);
    const z = Math.floor(first.z / cellSize);

    for (let offsetX = -1; offsetX <= 1; offsetX += 1) {
      for (let offsetY = -1; offsetY <= 1; offsetY += 1) {
        for (let offsetZ = -1; offsetZ <= 1; offsetZ += 1) {
          for (const candidate of cells.get(
            cellKey(x + offsetX, y + offsetY, z + offsetZ),
          ) ?? []) {
            if (candidate.index > firstIndex) callback(first, candidate.node);
          }
        }
      }
    }
  }
};

const hash = (value: string) => {
  let result = 2166136261;

  for (let index = 0; index < value.length; index += 1) {
    result ^= value.charCodeAt(index);
    result = Math.imul(result, 16777619);
  }

  return result >>> 0;
};

const randomSource = (seed: number) => {
  let state = seed || 0x9e3779b9;

  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 4294967296;
  };
};

const nodeMass = (node: ApiFederationUniverseNode) =>
  1 + Math.log10(1 + node.users) + Math.log1p(1 + node.posts) * 2.5;

const aggregateEdges = (
  universe: ApiFederationUniverse,
  byId: Map<string, UniverseNode>,
): LayoutEdge[] => {
  const interactionsByPair = new Map<string, number>();

  for (const edge of universe.edges) {
    if (edge.source === edge.target) continue;

    const pair = [edge.source, edge.target].sort();
    const key = `${pair[0]}\0${pair[1]}`;
    interactionsByPair.set(
      key,
      (interactionsByPair.get(key) ?? 0) + edge.interactions,
    );
  }

  return [...interactionsByPair]
    .sort(([first], [second]) => (first < second ? -1 : first > second ? 1 : 0))
    .flatMap(([key, interactions]) => {
      const [sourceId, targetId] = key.split('\0');
      const source = sourceId ? byId.get(sourceId) : undefined;
      const target = targetId ? byId.get(targetId) : undefined;

      return source && target ? [{ source, target, interactions }] : [];
    });
};

export const buildUniverseLayout = (
  universe: ApiFederationUniverse,
): UniverseNode[] => {
  const nodes = universe.nodes.map((node) => {
    const mass = nodeMass(node);
    const random = randomSource(hash(`sharlayan-universe:${node.domain}`));
    const longitude = random() * Math.PI * 2;
    const latitude = Math.acos(2 * random() - 1);
    const distance = (420 + random() * 760) / (1 + mass * 0.03);

    return {
      ...node,
      x: node.local ? 0 : distance * Math.sin(latitude) * Math.cos(longitude),
      y: node.local ? 0 : distance * Math.cos(latitude),
      z: node.local ? 0 : distance * Math.sin(latitude) * Math.sin(longitude),
      radius: Math.min(7, 1.5 + mass * 0.44),
      mass,
    };
  });
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const edges = aggregateEdges(universe, byId);

  for (let iteration = 0; iteration < LAYOUT_ITERATIONS; iteration += 1) {
    const movement = new Map(
      nodes.map((node) => [node.id, { x: 0, y: 0, z: 0 }]),
    );
    const cooling = 1 - iteration / LAYOUT_ITERATIONS;

    for (const edge of edges) {
      const { source, target } = edge;

      const dx = target.x - source.x;
      const dy = target.y - source.y;
      const dz = target.z - source.z;
      const distance = Math.max(1, Math.hypot(dx, dy, dz));
      const affinity = Math.min(
        1,
        Math.log1p(edge.interactions) / STRONG_INTERACTION_REFERENCE,
      );
      const constellationWeight = source.local || target.local ? 0.32 : 1.45;
      const desired = 58 + 250 * (1 - affinity) ** 2;
      const force =
        ((distance - desired) / distance) *
        (0.006 + affinity ** 2 * 0.11) *
        constellationWeight *
        (0.35 + cooling * 0.65);
      const sourceShare = target.mass / (source.mass + target.mass);
      const targetShare = source.mass / (source.mass + target.mass);
      const sourceMovement = movement.get(source.id);
      const targetMovement = movement.get(target.id);

      if (!source.local && sourceMovement) {
        sourceMovement.x += dx * force * sourceShare;
        sourceMovement.y += dy * force * sourceShare;
        sourceMovement.z += dz * force * sourceShare;
      }
      if (!target.local && targetMovement) {
        targetMovement.x -= dx * force * targetShare;
        targetMovement.y -= dy * force * targetShare;
        targetMovement.z -= dz * force * targetShare;
      }
    }

    if (iteration % REPULSION_INTERVAL === 0) {
      forEachNearbyPair(nodes, REPULSION_CELL_SIZE, (first, second) => {
        const dx = second.x - first.x;
        const dy = second.y - first.y;
        const dz = second.z - first.z;
        const distanceSquared = Math.max(100, dx * dx + dy * dy + dz * dz);
        const distance = Math.sqrt(distanceSquared);
        const force =
          (1_800 * REPULSION_INTERVAL * (0.25 + cooling * 0.75)) /
          distanceSquared /
          distance;
        const firstMovement = movement.get(first.id);
        const secondMovement = movement.get(second.id);

        if (!first.local && firstMovement) {
          firstMovement.x -= dx * force;
          firstMovement.y -= dy * force;
          firstMovement.z -= dz * force;
        }
        if (!second.local && secondMovement) {
          secondMovement.x += dx * force;
          secondMovement.y += dy * force;
          secondMovement.z += dz * force;
        }
      });
    }

    for (const node of nodes) {
      if (node.local) continue;

      const delta = movement.get(node.id);
      if (!delta) continue;

      const magnitude = Math.hypot(delta.x, delta.y, delta.z);
      const limit = 18 * (0.25 + cooling * 0.75);
      const scale = magnitude > limit ? limit / magnitude : 1;
      const gravity = 0.00022 + node.mass * 0.00001;
      node.x = node.x * (1 - gravity) + delta.x * scale;
      node.y = node.y * (1 - gravity) + delta.y * scale;
      node.z = node.z * (1 - gravity) + delta.z * scale;
    }
  }

  for (let iteration = 0; iteration < 24; iteration += 1) {
    forEachNearbyPair(nodes, COLLISION_CELL_SIZE, (first, second) => {
      const dx = second.x - first.x;
      const dy = second.y - first.y;
      const dz = second.z - first.z;
      const distance = Math.max(0.001, Math.hypot(dx, dy, dz));
      const minimumDistance = 34 + (first.radius + second.radius) * 1.6;
      if (distance >= minimumDistance) return;

      const force = ((minimumDistance - distance) / distance) * 0.32;
      const firstShare = second.mass / (first.mass + second.mass);
      const secondShare = first.mass / (first.mass + second.mass);

      if (!first.local) {
        first.x -= dx * force * firstShare;
        first.y -= dy * force * firstShare;
        first.z -= dz * force * firstShare;
      }
      if (!second.local) {
        second.x += dx * force * secondShare;
        second.y += dy * force * secondShare;
        second.z += dz * force * secondShare;
      }
    });
  }

  for (const node of nodes) {
    if (node.local) continue;

    node.x *= WORLD_SCALE;
    node.y *= WORLD_SCALE;
    node.z *= WORLD_SCALE;
  }

  return nodes;
};
