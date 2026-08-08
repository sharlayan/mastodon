import { blackHoleOrientation } from './black_hole';

const length = (vector: { x: number; y: number; z: number }) =>
  Math.hypot(vector.x, vector.y, vector.z);

const dot = (
  first: { x: number; y: number; z: number },
  second: { x: number; y: number; z: number },
) => first.x * second.x + first.y * second.y + first.z * second.z;

describe('federation universe black-hole orientation', () => {
  it('keeps the same seeded three-dimensional axis for a domain', () => {
    expect(blackHoleOrientation('gone.example')).toEqual(
      blackHoleOrientation('gone.example'),
    );
  });

  it('gives different domains different axes', () => {
    expect(blackHoleOrientation('first.example').axis).not.toEqual(
      blackHoleOrientation('second.example').axis,
    );
  });

  it('builds an orthonormal accretion-disc plane', () => {
    const { axis, planeX, planeY } = blackHoleOrientation('gone.example');

    expect(length(axis)).toBeCloseTo(1);
    expect(length(planeX)).toBeCloseTo(1);
    expect(length(planeY)).toBeCloseTo(1);
    expect(dot(axis, planeX)).toBeCloseTo(0);
    expect(dot(axis, planeY)).toBeCloseTo(0);
    expect(dot(planeX, planeY)).toBeCloseTo(0);
  });
});
