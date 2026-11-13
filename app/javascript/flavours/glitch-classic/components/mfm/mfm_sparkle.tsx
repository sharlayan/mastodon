import type React from 'react';
import { useRef, useEffect, useState, useCallback } from 'react';

import { useMfmHover } from './mfm_hover_context';

interface Particle {
  id: number;
  x: number;
  y: number;
  size: number;
  color: string;
  duration: number;
  createdAt: number;
}

const COLORS = ['#FF1493', '#00FFFF', '#FFE202'];

export const MfmSparkle: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const containerRef = useRef<HTMLSpanElement>(null);
  const nextParticleId = useRef(0);
  const [particles, setParticles] = useState<Particle[]>([]);
  const containerHovered = useMfmHover();
  const [selfHovered, setSelfHovered] = useState(false);
  const hovered = containerHovered || selfHovered;
  const handleMouseEnter = useCallback(() => {
    setSelfHovered(true);
  }, []);
  const handleMouseLeave = useCallback(() => {
    setSelfHovered(false);
  }, []);

  const createParticle = useCallback(() => {
    const el = containerRef.current;
    if (!el) return;

    const rect = el.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) return;

    const particle: Particle = {
      id: nextParticleId.current++,
      x: Math.random() * rect.width,
      y: Math.random() * rect.height,
      size: 1 + Math.random() * 8,
      color: COLORS[Math.floor(Math.random() * COLORS.length)] ?? '#FF1493',
      duration: 1000 + Math.random() * 1000,
      createdAt: Date.now(),
    };

    setParticles((prev) => [...prev, particle]);

    setTimeout(() => {
      setParticles((prev) => prev.filter((p) => p.id !== particle.id));
    }, particle.duration);
  }, []);

  useEffect(() => {
    if (!hovered) return;

    const interval = setInterval(createParticle, 500 + Math.random() * 500);
    for (let i = 0; i < 3; i++) {
      setTimeout(createParticle, i * 200);
    }
    return () => {
      clearInterval(interval);
      setParticles([]);
    };
  }, [hovered, createParticle]);

  return (
    <span
      ref={containerRef}
      className='mfm-sparkle'
      style={{ display: 'inline-block', position: 'relative' }}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {children}
      {particles.map((p) => (
        <svg
          key={p.id}
          className='mfm-sparkle-particle'
          style={{
            position: 'absolute',
            left: `${p.x}px`,
            top: `${p.y}px`,
            pointerEvents: 'none',
            animation: `mfm-sparkle-anim ${p.duration}ms linear forwards`,
            width: `${p.size * 4}px`,
            height: `${p.size * 4}px`,
          }}
          viewBox='0 0 16 16'
        >
          <polygon
            points='8,0 10,6 16,8 10,10 8,16 6,10 0,8 6,6'
            fill={p.color}
          />
        </svg>
      ))}
    </span>
  );
};
