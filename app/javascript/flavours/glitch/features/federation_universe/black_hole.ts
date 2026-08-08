export interface Vector3 {
  x: number;
  y: number;
  z: number;
}

export interface BlackHoleOrientation {
  axis: Vector3;
  planeX: Vector3;
  planeY: Vector3;
}

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

const normalize = (vector: Vector3): Vector3 => {
  const length = Math.max(0.000001, Math.hypot(vector.x, vector.y, vector.z));

  return {
    x: vector.x / length,
    y: vector.y / length,
    z: vector.z / length,
  };
};

const cross = (first: Vector3, second: Vector3): Vector3 => ({
  x: first.y * second.z - first.z * second.y,
  y: first.z * second.x - first.x * second.z,
  z: first.x * second.y - first.y * second.x,
});

const orientations = new Map<string, BlackHoleOrientation>();

export const blackHoleOrientation = (domain: string): BlackHoleOrientation => {
  const existing = orientations.get(domain);
  if (existing) return existing;

  const random = randomSource(
    hash(`sharlayan-universe:${domain}:black-hole-axis`),
  );
  const vertical = random() * 2 - 1;
  const longitude = random() * Math.PI * 2;
  const horizontal = Math.sqrt(1 - vertical * vertical);
  const axis = {
    x: Math.cos(longitude) * horizontal,
    y: vertical,
    z: Math.sin(longitude) * horizontal,
  };
  const reference =
    Math.abs(axis.y) < 0.9 ? { x: 0, y: 1, z: 0 } : { x: 1, y: 0, z: 0 };
  const planeX = normalize(cross(axis, reference));
  const planeY = normalize(cross(axis, planeX));

  const orientation = { axis, planeX, planeY };
  orientations.set(domain, orientation);

  return orientation;
};
