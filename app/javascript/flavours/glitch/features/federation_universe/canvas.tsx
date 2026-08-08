import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import type {
  ApiFederationUniverse,
  ApiFederationUniverseEdge,
} from 'flavours/glitch/api/federation_universe';
import { reduceMotion } from 'flavours/glitch/initial_state';

import { blackHoleOrientation } from './black_hole';
import type { Vector3 } from './black_hole';
import type { UniverseNode } from './layout';

const messages = defineMessages({
  canvasLabel: {
    id: 'federation_universe.canvas_label',
    defaultMessage: 'Interactive three-dimensional federation map',
  },
  interactions: {
    id: 'federation_universe.interactions',
    defaultMessage: '{count, number} interactions',
  },
});

interface ProjectedNode {
  node: UniverseNode;
  x: number;
  y: number;
  z: number;
  radius: number;
  perspective: number;
  visible: boolean;
}

interface Camera {
  yaw: number;
  pitch: number;
  zoom: number;
  x: number;
  y: number;
  z: number;
}

const STAR_COUNT = 220;
const FORWARD_STEP = 700;
const LATERAL_STEP = 550;
const VERTICAL_STEP = 550;
const CAMERA_MOVE_TIME = 420;
const VERTICAL_FIELD_OF_VIEW = (65 * Math.PI) / 180;
const STAR_FIELD = Array.from({ length: STAR_COUNT }, (_, index) => {
  const y = 1 - (index / (STAR_COUNT - 1)) * 2;
  const radius = Math.sqrt(1 - y * y);
  const angle = index * Math.PI * (3 - Math.sqrt(5));

  return {
    x: Math.cos(angle) * radius,
    y,
    z: Math.sin(angle) * radius,
    brightness: 0.28 + ((index * 37) % 70) / 100,
    size: index % 13 === 0 ? 1.7 : 0.85,
  };
});

const rotateNode = (node: Vector3, camera: Camera) => {
  const cosYaw = Math.cos(camera.yaw);
  const sinYaw = Math.sin(camera.yaw);
  const cosPitch = Math.cos(camera.pitch);
  const sinPitch = Math.sin(camera.pitch);
  const relativeX = node.x - camera.x;
  const relativeY = node.y - camera.y;
  const relativeZ = node.z - camera.z;
  const x = relativeX * cosYaw - relativeZ * sinYaw;
  const yawZ = relativeX * sinYaw + relativeZ * cosYaw;

  return {
    x,
    y: relativeY * cosPitch - yawZ * sinPitch,
    z: relativeY * sinPitch + yawZ * cosPitch,
  };
};

const projectPosition = (
  position: Vector3,
  camera: Camera,
  width: number,
  height: number,
) => {
  const rotated = rotateNode(position, camera);
  const depth = 920 + rotated.z;
  const focalLength = height / (2 * Math.tan(VERTICAL_FIELD_OF_VIEW / 2));
  const perspective = (focalLength * camera.zoom) / Math.max(240, depth);

  return {
    x: width / 2 + rotated.x * perspective,
    y: height / 2 + rotated.y * perspective,
    z: rotated.z,
    perspective,
    visible: depth > 240,
  };
};

const rotateStar = (star: (typeof STAR_FIELD)[number], camera: Camera) => {
  const cosYaw = Math.cos(camera.yaw);
  const sinYaw = Math.sin(camera.yaw);
  const cosPitch = Math.cos(camera.pitch);
  const sinPitch = Math.sin(camera.pitch);
  const x = star.x * cosYaw - star.z * sinYaw;
  const yawZ = star.x * sinYaw + star.z * cosYaw;

  return {
    x,
    y: star.y * cosPitch - yawZ * sinPitch,
    z: star.y * sinPitch + yawZ * cosPitch,
  };
};

const projectNodes = (
  nodes: UniverseNode[],
  camera: Camera,
  width: number,
  height: number,
) =>
  nodes.map((node): ProjectedNode => {
    const projected = projectPosition(node, camera, width, height);

    return {
      node,
      ...projected,
      radius: Math.max(2, node.radius * projected.perspective),
    };
  });

const findPoint = (points: ProjectedNode[], x: number, y: number) => {
  let closest: ProjectedNode | undefined;
  let closestDistance = 24;

  for (const point of points) {
    if (!point.visible) continue;

    const distance = Math.hypot(point.x - x, point.y - y) - point.radius;
    if (distance < closestDistance) {
      closest = point;
      closestDistance = distance;
    }
  }

  return closest;
};

const drawGlow = (
  context: CanvasRenderingContext2D,
  point: ProjectedNode,
  selected: boolean,
  hovered: boolean,
) => {
  const candidateColor = point.node.color;
  const validColor =
    candidateColor && /^#[0-9a-f]{6}$/i.test(candidateColor)
      ? candidateColor
      : '#858afa';
  const red = Number.parseInt(validColor.slice(1, 3), 16);
  const green = Number.parseInt(validColor.slice(3, 5), 16);
  const blue = Number.parseInt(validColor.slice(5, 7), 16);
  const color =
    red * 0.299 + green * 0.587 + blue * 0.114 < 52 ? '#858afa' : validColor;
  const glowRadius = point.radius * (selected ? 3.4 : hovered ? 2.9 : 1.95);
  const glow = context.createRadialGradient(
    point.x,
    point.y,
    0,
    point.x,
    point.y,
    glowRadius,
  );
  glow.addColorStop(0, color);
  glow.addColorStop(0.18, `${color}a8`);
  glow.addColorStop(1, `${color}00`);
  context.fillStyle = glow;
  context.beginPath();
  context.arc(point.x, point.y, glowRadius, 0, Math.PI * 2);
  context.fill();

  context.fillStyle = selected || hovered ? '#ffffff' : color;
  context.beginPath();
  context.arc(point.x, point.y, point.radius, 0, Math.PI * 2);
  context.fill();
};

const drawBlackHole = (
  context: CanvasRenderingContext2D,
  point: ProjectedNode,
  selected: boolean,
  hovered: boolean,
  camera: Camera,
  width: number,
  height: number,
) => {
  const eventHorizon = Math.max(
    2.8,
    point.radius * (selected ? 1.5 : hovered ? 1.4 : 1.2),
  );
  const orientation = blackHoleOrientation(point.node.domain);
  const worldHorizon = eventHorizon / Math.max(0.02, point.perspective);
  const drawDiscRing = (radius: number, color: string, lineWidth: number) => {
    context.strokeStyle = color;
    context.lineWidth = lineWidth;
    context.beginPath();

    for (let step = 0; step <= 64; step += 1) {
      const angle = (step / 64) * Math.PI * 2;
      const cosine = Math.cos(angle);
      const sine = Math.sin(angle);
      const projected = projectPosition(
        {
          x:
            point.node.x +
            (orientation.planeX.x * cosine + orientation.planeY.x * sine) *
              radius,
          y:
            point.node.y +
            (orientation.planeX.y * cosine + orientation.planeY.y * sine) *
              radius,
          z:
            point.node.z +
            (orientation.planeX.z * cosine + orientation.planeY.z * sine) *
              radius,
        },
        camera,
        width,
        height,
      );

      if (step === 0) context.moveTo(projected.x, projected.y);
      else context.lineTo(projected.x, projected.y);
    }

    context.closePath();
    context.stroke();
  };

  context.save();
  context.globalCompositeOperation = 'lighter';
  drawDiscRing(
    worldHorizon * 3.9,
    'rgba(126, 91, 255, 0.3)',
    eventHorizon * 0.72,
  );
  drawDiscRing(
    worldHorizon * 3.15,
    'rgba(255, 145, 56, 0.72)',
    eventHorizon * 0.48,
  );
  drawDiscRing(
    worldHorizon * 2.45,
    'rgba(255, 246, 211, 0.92)',
    eventHorizon * 0.23,
  );
  context.restore();

  const lensing = context.createRadialGradient(
    point.x,
    point.y,
    eventHorizon * 0.75,
    point.x,
    point.y,
    eventHorizon * 2.15,
  );
  lensing.addColorStop(0, 'rgba(255, 255, 255, 0)');
  lensing.addColorStop(0.48, 'rgba(204, 174, 255, 0.52)');
  lensing.addColorStop(1, 'rgba(126, 91, 255, 0)');
  context.fillStyle = lensing;
  context.beginPath();
  context.arc(point.x, point.y, eventHorizon * 2.15, 0, Math.PI * 2);
  context.fill();

  context.fillStyle = '#000000';
  context.beginPath();
  context.arc(point.x, point.y, eventHorizon, 0, Math.PI * 2);
  context.fill();
  context.strokeStyle = 'rgba(255, 241, 211, 0.82)';
  context.lineWidth = Math.max(0.65, eventHorizon * 0.16);
  context.stroke();

  if (selected || hovered) {
    context.strokeStyle = selected
      ? 'rgba(151, 220, 255, 0.9)'
      : 'rgba(255, 255, 255, 0.72)';
    context.lineWidth = 1;
    context.beginPath();
    context.arc(point.x, point.y, eventHorizon * 1.55, 0, Math.PI * 2);
    context.stroke();
  }
};

export const FederationUniverseCanvas: React.FC<{
  universe: ApiFederationUniverse;
  nodes: UniverseNode[];
  selectedId: string | null;
  onSelect: (node: UniverseNode | null) => void;
}> = ({ universe, nodes, selectedId, onSelect }) => {
  const intl = useIntl();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const frameRef = useRef(0);
  const projectedRef = useRef<ProjectedNode[]>([]);
  const cameraRef = useRef<Camera>({
    yaw: -0.35,
    pitch: 0.18,
    zoom: 1,
    x: 0,
    y: 0,
    z: 0,
  });
  const cameraTargetRef = useRef({ x: 0, y: 0, z: 0 });
  const dragRef = useRef({ active: false, moved: false, x: 0, y: 0 });
  const hoveredRef = useRef<string | null>(null);
  const selectedRef = useRef(selectedId);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const edgesByNode = useMemo(() => {
    const result = new Map<string, ApiFederationUniverseEdge[]>();
    for (const edge of universe.edges) {
      result.set(edge.source, [...(result.get(edge.source) ?? []), edge]);
      result.set(edge.target, [...(result.get(edge.target) ?? []), edge]);
    }
    return result;
  }, [universe.edges]);

  useEffect(() => {
    selectedRef.current = selectedId;
    const selected = nodes.find((node) => node.id === selectedId);
    if (selected) {
      cameraTargetRef.current = {
        x: selected.x,
        y: selected.y,
        z: selected.z,
      };
    }
  }, [nodes, selectedId]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;

    const context = canvas.getContext('2d');
    if (!context) return undefined;

    let lastTime = performance.now();
    let width = 0;
    let height = 0;
    let pixelRatio = 1;

    const resize = () => {
      const bounds = canvas.getBoundingClientRect();
      width = Math.max(1, bounds.width);
      height = Math.max(1, bounds.height);
      pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.round(width * pixelRatio);
      canvas.height = Math.round(height * pixelRatio);
    };
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    resize();

    const render = (time: number) => {
      const elapsed = Math.min(40, time - lastTime);
      lastTime = time;
      if (!reduceMotion && !dragRef.current.active) {
        cameraRef.current.yaw += elapsed * 0.000025;
      }
      const cameraBlend = reduceMotion
        ? 1
        : 1 - Math.exp(-elapsed / CAMERA_MOVE_TIME);
      cameraRef.current.x +=
        (cameraTargetRef.current.x - cameraRef.current.x) * cameraBlend;
      cameraRef.current.y +=
        (cameraTargetRef.current.y - cameraRef.current.y) * cameraBlend;
      cameraRef.current.z +=
        (cameraTargetRef.current.z - cameraRef.current.z) * cameraBlend;

      context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
      context.clearRect(0, 0, width, height);

      const background = context.createRadialGradient(
        width * 0.48,
        height * 0.45,
        0,
        width * 0.5,
        height * 0.5,
        Math.max(width, height) * 0.8,
      );
      background.addColorStop(0, '#111936');
      background.addColorStop(0.52, '#080d20');
      background.addColorStop(1, '#02040b');
      context.fillStyle = background;
      context.fillRect(0, 0, width, height);

      for (const star of STAR_FIELD) {
        const rotated = rotateStar(star, cameraRef.current);
        if (rotated.z > 0) continue;

        const x = width / 2 + rotated.x * width * 0.68;
        const y = height / 2 + rotated.y * height * 0.68;
        if (x < 0 || x > width || y < 0 || y > height) continue;

        const alpha = star.brightness * (0.45 + -rotated.z * 0.55);
        context.fillStyle = `rgba(210, 225, 255, ${alpha})`;
        context.fillRect(x, y, star.size, star.size);
      }

      const points = projectNodes(nodes, cameraRef.current, width, height);
      const pointsById = new Map(points.map((point) => [point.node.id, point]));
      projectedRef.current = points;
      const focusId = selectedRef.current;
      const focus = focusId ? pointsById.get(focusId) : undefined;
      const connected = new Map<string, number>();
      if (focusId) {
        for (const edge of edgesByNode.get(focusId) ?? []) {
          const connectedId =
            edge.source === focusId ? edge.target : edge.source;
          connected.set(
            connectedId,
            (connected.get(connectedId) ?? 0) + edge.interactions,
          );
        }
      }

      context.lineCap = 'round';
      for (const [connectedId, interactions] of connected) {
        const target = pointsById.get(connectedId);
        if (!focus || !target) continue;
        const margin = 80;
        const focusInViewport =
          focus.x >= -margin &&
          focus.x <= width + margin &&
          focus.y >= -margin &&
          focus.y <= height + margin;
        const targetInViewport =
          target.x >= -margin &&
          target.x <= width + margin &&
          target.y >= -margin &&
          target.y <= height + margin;
        if (
          !focus.visible ||
          !target.visible ||
          (!focusInViewport && !targetInViewport)
        )
          continue;

        const strength = Math.min(1, Math.log1p(interactions) / 8);
        const depth = Math.max(
          0.12,
          Math.min(1, 1 - (focus.z + target.z) / 1600),
        );
        context.strokeStyle = `rgba(151, 220, 255, ${(0.18 + strength * 0.26) * depth})`;
        context.lineWidth = 0.55 + strength * 1.05;
        context.beginPath();
        context.moveTo(focus.x, focus.y);
        context.lineTo(target.x, target.y);
        context.stroke();
      }

      points
        .filter((point) => point.visible)
        .sort((first, second) => second.z - first.z)
        .forEach((point) => {
          const selected = selectedRef.current === point.node.id;
          const hovered = hoveredRef.current === point.node.id;
          if (point.node.gone) {
            drawBlackHole(
              context,
              point,
              selected,
              hovered,
              cameraRef.current,
              width,
              height,
            );
          } else {
            drawGlow(context, point, selected, hovered);
          }

          if (selected || hovered || point.node.local) {
            context.font = `${selected ? 600 : 500} 12px system-ui, sans-serif`;
            context.textAlign = 'center';
            context.textBaseline = 'bottom';
            context.fillStyle = 'rgba(2, 4, 11, 0.82)';
            context.fillText(
              point.node.name,
              point.x + 1,
              point.y - point.radius - 7 + 1,
            );
            context.fillStyle = '#f2f6ff';
            context.fillText(
              point.node.name,
              point.x,
              point.y - point.radius - 7,
            );
          }
        });

      frameRef.current = requestAnimationFrame(render);
    };

    frameRef.current = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(frameRef.current);
      observer.disconnect();
    };
  }, [edgesByNode, nodes]);

  const pointerPosition = useCallback((event: React.PointerEvent) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
  }, []);

  const handlePointerDown = useCallback(
    (event: React.PointerEvent<HTMLCanvasElement>) => {
      event.currentTarget.focus();
      event.currentTarget.setPointerCapture(event.pointerId);
      dragRef.current = {
        active: true,
        moved: false,
        x: event.clientX,
        y: event.clientY,
      };
    },
    [],
  );

  const handlePointerMove = useCallback(
    (event: React.PointerEvent<HTMLCanvasElement>) => {
      if (dragRef.current.active) {
        const dx = event.clientX - dragRef.current.x;
        const dy = event.clientY - dragRef.current.y;
        if (Math.abs(dx) + Math.abs(dy) > 2) dragRef.current.moved = true;
        cameraRef.current.yaw += dx * 0.006;
        cameraRef.current.pitch = Math.max(
          -1.25,
          Math.min(1.25, cameraRef.current.pitch + dy * 0.005),
        );
        dragRef.current.x = event.clientX;
        dragRef.current.y = event.clientY;
        return;
      }

      const position = pointerPosition(event);
      const point = findPoint(projectedRef.current, position.x, position.y);
      const nextId = point?.node.id ?? null;
      if (nextId !== hoveredRef.current) {
        hoveredRef.current = nextId;
        setHoveredId(nextId);
      }
    },
    [pointerPosition],
  );

  const handlePointerUp = useCallback(
    (event: React.PointerEvent<HTMLCanvasElement>) => {
      const wasMoved = dragRef.current.moved;
      dragRef.current.active = false;
      if (wasMoved) return;

      const position = pointerPosition(event);
      onSelect(
        findPoint(projectedRef.current, position.x, position.y)?.node ?? null,
      );
    },
    [onSelect, pointerPosition],
  );

  const handleWheel = useCallback((event: React.WheelEvent) => {
    event.preventDefault();
    cameraRef.current.zoom = Math.max(
      0.48,
      Math.min(2.8, cameraRef.current.zoom * Math.exp(-event.deltaY * 0.001)),
    );
  }, []);

  const handlePointerCancel = useCallback(() => {
    dragRef.current.active = false;
  }, []);

  const handlePointerLeave = useCallback(() => {
    hoveredRef.current = null;
    setHoveredId(null);
  }, []);

  const handleKeyDown = useCallback((event: React.KeyboardEvent) => {
    const camera = cameraRef.current;
    const target = cameraTargetRef.current;
    const key = event.key.toLowerCase();
    const rightX = Math.cos(camera.yaw);
    const rightZ = -Math.sin(camera.yaw);
    const forwardX = Math.sin(camera.yaw) * Math.cos(camera.pitch);
    const forwardY = Math.sin(camera.pitch);
    const forwardZ = Math.cos(camera.yaw) * Math.cos(camera.pitch);
    if (event.key === 'ArrowLeft') camera.yaw -= 0.12;
    else if (event.key === 'ArrowRight') camera.yaw += 0.12;
    else if (event.key === 'ArrowUp')
      camera.pitch = Math.max(-1.25, camera.pitch - 0.1);
    else if (event.key === 'ArrowDown')
      camera.pitch = Math.min(1.25, camera.pitch + 0.1);
    else if (event.key === '+' || event.key === '=')
      camera.zoom = Math.min(2.8, camera.zoom * 1.12);
    else if (event.key === '-')
      camera.zoom = Math.max(0.48, camera.zoom / 1.12);
    else if (key === 'w') {
      target.x += forwardX * FORWARD_STEP;
      target.y += forwardY * FORWARD_STEP;
      target.z += forwardZ * FORWARD_STEP;
    } else if (key === 's') {
      target.x -= forwardX * FORWARD_STEP;
      target.y -= forwardY * FORWARD_STEP;
      target.z -= forwardZ * FORWARD_STEP;
    } else if (key === 'a') {
      target.x -= rightX * LATERAL_STEP;
      target.z -= rightZ * LATERAL_STEP;
    } else if (key === 'd') {
      target.x += rightX * LATERAL_STEP;
      target.z += rightZ * LATERAL_STEP;
    } else if (event.key === ' ') target.y -= VERTICAL_STEP;
    else if (key === 'c') target.y += VERTICAL_STEP;
    else return;
    event.preventDefault();
  }, []);

  const hoveredNode = hoveredId
    ? nodes.find((node) => node.id === hoveredId)
    : undefined;
  const hoveredInteractions = hoveredNode
    ? (edgesByNode.get(hoveredNode.id) ?? []).reduce(
        (total, edge) => total + edge.interactions,
        0,
      )
    : 0;

  return (
    <div className='federation-universe__viewport'>
      <canvas
        ref={canvasRef}
        className='federation-universe__canvas'
        tabIndex={0}
        aria-label={intl.formatMessage(messages.canvasLabel)}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerCancel}
        onPointerLeave={handlePointerLeave}
        onWheel={handleWheel}
        onKeyDown={handleKeyDown}
      />
      {hoveredNode && hoveredNode.id !== selectedId && (
        <div className='federation-universe__tooltip' role='status'>
          <strong>{hoveredNode.name}</strong>
          <span>{hoveredNode.domain}</span>
          <span>
            {intl.formatMessage(messages.interactions, {
              count: hoveredInteractions,
            })}
          </span>
        </div>
      )}
    </div>
  );
};
