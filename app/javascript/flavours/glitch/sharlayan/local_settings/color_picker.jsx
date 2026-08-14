import { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';

import { useIntl } from 'react-intl';

const clamp = (value, minimum, maximum) => Math.min(maximum, Math.max(minimum, value));

const rgbToHsl = (red, green, blue, alpha = 1) => {
  const [r, g, b] = [red, green, blue].map(value => clamp(value, 0, 255) / 255);
  const maximum = Math.max(r, g, b);
  const minimum = Math.min(r, g, b);
  const lightness = (maximum + minimum) / 2;
  const difference = maximum - minimum;
  if (difference === 0) return { hue: 0, saturation: 0, lightness: Math.round(lightness * 100), alpha };

  const saturation = difference / (1 - Math.abs(2 * lightness - 1));
  let hue;
  if (maximum === r) hue = 60 * (((g - b) / difference) % 6);
  else if (maximum === g) hue = 60 * ((b - r) / difference + 2);
  else hue = 60 * ((r - g) / difference + 4);

  return {
    hue: Math.round(hue < 0 ? hue + 360 : hue),
    saturation: Math.round(saturation * 100),
    lightness: Math.round(lightness * 100),
    alpha,
  };
};

const hslToRgb = ({ hue, saturation, lightness }) => {
  const h = ((hue % 360) + 360) % 360;
  const s = clamp(saturation, 0, 100) / 100;
  const l = clamp(lightness, 0, 100) / 100;
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const secondary = chroma * (1 - Math.abs((h / 60) % 2 - 1));
  const offset = l - chroma / 2;
  let channels;
  if (h < 60) channels = [chroma, secondary, 0];
  else if (h < 120) channels = [secondary, chroma, 0];
  else if (h < 180) channels = [0, chroma, secondary];
  else if (h < 240) channels = [0, secondary, chroma];
  else if (h < 300) channels = [secondary, 0, chroma];
  else channels = [chroma, 0, secondary];
  return channels.map(channel => Math.round((channel + offset) * 255));
};

const rgbToHex = (rgb) => `#${rgb.map(channel => channel.toString(16).padStart(2, '0')).join('')}`;

const parseColor = (value) => {
  const hex = /^#([0-9a-f]{3,8})$/i.exec(value.trim());
  if (hex && [3, 4, 6, 8].includes(hex[1].length)) {
    const expanded = hex[1].length <= 4 ? [...hex[1]].map(character => character.repeat(2)).join('') : hex[1];
    return rgbToHsl(
      Number.parseInt(expanded.slice(0, 2), 16),
      Number.parseInt(expanded.slice(2, 4), 16),
      Number.parseInt(expanded.slice(4, 6), 16),
      expanded.length === 8 ? Number.parseInt(expanded.slice(6, 8), 16) / 255 : 1,
    );
  }

  const rgb = /^rgba?\(\s*(\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)(?:\D+(0(?:\.\d+)?|1(?:\.0+)?|\d+(?:\.\d+)?%))?\s*\)$/i.exec(value.trim());
  if (rgb) {
    const alpha = rgb[4]?.endsWith('%') ? Number.parseFloat(rgb[4]) / 100 : Number.parseFloat(rgb[4] ?? '1');
    return rgbToHsl(Number.parseFloat(rgb[1]), Number.parseFloat(rgb[2]), Number.parseFloat(rgb[3]), alpha);
  }

  const hsl = /^hsla?\(\s*(-?\d+(?:\.\d+)?)\D+(\d+(?:\.\d+)?)%\D+(\d+(?:\.\d+)?)%(?:\D+(0(?:\.\d+)?|1(?:\.0+)?|\d+(?:\.\d+)?%))?\s*\)$/i.exec(value.trim());
  if (hsl) {
    const alpha = hsl[4]?.endsWith('%') ? Number.parseFloat(hsl[4]) / 100 : Number.parseFloat(hsl[4] ?? '1');
    return { hue: Number.parseFloat(hsl[1]), saturation: Number.parseFloat(hsl[2]), lightness: Number.parseFloat(hsl[3]), alpha };
  }

  return { hue: 0, saturation: 0, lightness: 0, alpha: 1 };
};

const serializeColor = ({ hue, saturation, lightness, alpha }) => `hsl(${Math.round(hue)} ${Math.round(saturation)}% ${Math.round(lightness)}% / ${Math.round(alpha * 100)}%)`;

const RgbInput = ({ channel, value, onChange }) => {
  const [draft, setDraft] = useState(String(value));
  const focused = useRef(false);

  useEffect(() => {
    if (!focused.current) setDraft(String(value));
  }, [value]);

  const update = (nextValue) => {
    setDraft(nextValue);
    if (nextValue === '') return;
    const parsed = Number.parseInt(nextValue, 10);
    if (!Number.isNaN(parsed)) onChange(parsed);
  };

  return (
    <label>
      <span>{channel}</span>
      <input
        type='number'
        min='0'
        max='255'
        value={draft}
        onFocus={() => { focused.current = true; }}
        onBlur={() => {
          focused.current = false;
          setDraft(String(value));
        }}
        onChange={event => update(event.target.value)}
      />
    </label>
  );
};

const ColorPicker = ({ value, variable, onChange }) => {
  const intl = useIntl();
  const [open, setOpen] = useState(false);
  const [color, setColor] = useState(() => parseColor(value));
  const [position, setPosition] = useState({ left: 12, top: 12, width: 300 });
  const container = useRef(null);
  const popover = useRef(null);

  useEffect(() => {
    if (!open) setColor(parseColor(value));
  }, [open, value]);

  useEffect(() => {
    if (!open) return undefined;
    const bounds = container.current.getBoundingClientRect();
    const width = Math.min(320, window.innerWidth - 24);
    const left = clamp(bounds.left, 12, window.innerWidth - width - 12);
    const spaceBelow = window.innerHeight - bounds.bottom;
    const top = spaceBelow >= 360 ? bounds.bottom + 6 : Math.max(12, bounds.top - 366);
    setPosition({ left, top, width });
    const close = (event) => {
      if (event.type === 'keydown' && event.key !== 'Escape') return;
      if (event.type === 'pointerdown' && (container.current?.contains(event.target) || popover.current?.contains(event.target))) return;
      setOpen(false);
    };
    document.addEventListener('pointerdown', close);
    document.addEventListener('keydown', close);
    window.addEventListener('resize', close);
    window.addEventListener('scroll', close, true);
    return () => {
      document.removeEventListener('pointerdown', close);
      document.removeEventListener('keydown', close);
      window.removeEventListener('resize', close);
      window.removeEventListener('scroll', close, true);
    };
  }, [open]);

  const update = (key, nextValue) => {
    const nextColor = { ...color, [key]: Number.parseFloat(nextValue) };
    setColor(nextColor);
    onChange(serializeColor(nextColor));
  };

  const rgb = hslToRgb(color);
  const updateRgb = (index, nextValue) => {
    const nextRgb = [...rgb];
    nextRgb[index] = clamp(nextValue, 0, 255);
    const nextColor = rgbToHsl(...nextRgb, color.alpha);
    setColor(nextColor);
    onChange(serializeColor(nextColor));
  };

  const updateHex = (nextValue) => {
    if (!/^#[0-9a-f]{6}$/i.test(nextValue.trim())) return;
    const parsed = parseColor(nextValue);
    const nextColor = { ...parsed, alpha: color.alpha };
    setColor(nextColor);
    onChange(serializeColor(nextColor));
  };

  const controls = [
    ['hue', 0, 360, 1, 'settings.user_theme.color.hue', 'Hue'],
    ['saturation', 0, 100, 1, 'settings.user_theme.color.saturation', 'Saturation'],
    ['lightness', 0, 100, 1, 'settings.user_theme.color.lightness', 'Lightness'],
    ['alpha', 0, 1, 0.01, 'settings.user_theme.color.alpha', 'Opacity'],
  ];
  const preview = serializeColor(color);

  return (
    <span className='user-theme__color-picker' ref={container}>
      <button
        type='button'
        className='user-theme__color-picker__trigger'
        aria-label={intl.formatMessage({ id: 'settings.user_theme.color.open', defaultMessage: 'Choose color for {variable}' }, { variable })}
        aria-expanded={open}
        onClick={() => setOpen(current => !current)}
      >
        <span style={{ backgroundColor: value || 'transparent' }} />
      </button>
      {open && createPortal(
        <span className='user-theme__color-picker__popover' ref={popover} style={position}>
          <span className='user-theme__color-picker__preview'><span style={{ backgroundColor: preview }} /></span>
          <label className='user-theme__color-picker__hex'>
            <span>HEX</span>
            <input key={rgbToHex(rgb)} type='text' defaultValue={rgbToHex(rgb)} pattern='#[0-9a-fA-F]{6}' onBlur={event => updateHex(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') event.currentTarget.blur(); }} />
          </label>
          <span className='user-theme__color-picker__rgb'>
            {['R', 'G', 'B'].map((channel, index) => (
              <RgbInput channel={channel} value={rgb[index]} onChange={nextValue => updateRgb(index, nextValue)} key={channel} />
            ))}
          </span>
          {controls.map(([key, minimum, maximum, step, messageId, defaultMessage]) => (
            <label key={key}>
              <span>{intl.formatMessage({ id: messageId, defaultMessage })}</span>
              <input type='range' min={minimum} max={maximum} step={step} value={color[key]} onChange={event => update(key, event.target.value)} />
              <output>{key === 'alpha' ? `${Math.round(color[key] * 100)}%` : Math.round(color[key])}</output>
            </label>
          ))}
        </span>,
        document.body,
      )}
    </span>
  );
};

export default ColorPicker;
