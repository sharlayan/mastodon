export interface DecorationTransformConfig {
  offset_x: number;
  offset_y: number;
  angle: number;
  flip_h: boolean;
  scale: number;
}

export function buildDecorationTransform(
  config: DecorationTransformConfig,
): string | undefined {
  const parts: string[] = [];
  if (config.offset_x || config.offset_y) {
    parts.push(
      `translate(${config.offset_x * 100}%, ${config.offset_y * 100}%)`,
    );
  }
  if (config.angle) parts.push(`rotate(${config.angle * 360}deg)`);
  if (config.flip_h) parts.push('scaleX(-1)');
  if (config.scale && config.scale !== 1) parts.push(`scale(${config.scale})`);
  return parts.join(' ') || undefined;
}
