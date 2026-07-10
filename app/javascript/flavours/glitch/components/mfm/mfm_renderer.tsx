import React, { useCallback, useMemo, useState } from 'react';

import * as mfm from 'mfm-js';

import { Emoji } from '@/flavours/glitch/components/emoji';
import {
  AnimateEmojiProvider,
  CustomEmojiProvider,
} from '@/flavours/glitch/components/emoji/context';
import type { CustomEmojiMapArg } from '@/flavours/glitch/features/emoji/types';

import {
  MFM_ALLOWED_TAGS,
  MFM_ALLOWED_FONTS,
  MFM_ALLOWED_BORDER_STYLES,
  MFM_MAX_SCALE,
  MFM_PROFILE_ALLOWED_TAGS,
  MFM_SENSITIVE_FOLD_TAGS,
} from './mfm_constants';
import { MfmHoverContext } from './mfm_hover_context';
import { validTime, validColor, safeParseFloat, clamp } from './mfm_security';
import { MfmSparkle } from './mfm_sparkle';

export function hasSensitiveFoldTags(text: string): boolean {
  try {
    const ast = mfm.parse(text);
    let found = false;
    mfm.inspect(ast, (node) => {
      if (found) return;
      if (node.type === 'fn' && MFM_SENSITIVE_FOLD_TAGS.has(node.props.name)) {
        found = true;
      }
    });
    return found;
  } catch {
    return false;
  }
}

export function hasAnyMfmFn(text: string): boolean {
  try {
    const ast = mfm.parse(text);
    let found = false;
    mfm.inspect(ast, (node) => {
      if (found) return;
      if (node.type === 'fn') found = true;
    });
    return found;
  } catch {
    return false;
  }
}

interface MfmRendererProps {
  text: string;
  emojis?: CustomEmojiMapArg | null;
  isProfile?: boolean;
  animationsEnabled?: boolean;
}

export const MfmRenderer: React.FC<MfmRendererProps> = ({
  text,
  emojis,
  isProfile = false,
  animationsEnabled = true,
}) => {
  const ast = useMemo(() => {
    try {
      return mfm.parse(text);
    } catch {
      return null;
    }
  }, [text]);

  const [hovered, setHovered] = useState(false);
  const handleMouseEnter = useCallback(() => {
    setHovered(true);
  }, []);
  const handleMouseLeave = useCallback(() => {
    setHovered(false);
  }, []);

  if (!ast) {
    return <span>{text}</span>;
  }

  const allowedTags = isProfile ? MFM_PROFILE_ALLOWED_TAGS : MFM_ALLOWED_TAGS;

  return (
    <CustomEmojiProvider emojis={emojis}>
      <MfmHoverContext.Provider value={hovered}>
        <AnimateEmojiProvider
          as='span'
          className='mfm-container'
          onMouseEnter={handleMouseEnter}
          onMouseLeave={handleMouseLeave}
        >
          {renderNodes(ast, allowedTags, animationsEnabled)}
        </AnimateEmojiProvider>
      </MfmHoverContext.Provider>
    </CustomEmojiProvider>
  );
};

function renderNodes(
  nodes: mfm.MfmNode[],
  allowedTags: Set<string>,
  animationsEnabled: boolean,
): React.ReactNode[] {
  return nodes.map((node, i) =>
    renderNode(node, i, allowedTags, animationsEnabled),
  );
}

function renderNode(
  node: mfm.MfmNode,
  key: number,
  allowedTags: Set<string>,
  animationsEnabled: boolean,
): React.ReactNode {
  const children = node.children
    ? renderNodes(node.children, allowedTags, animationsEnabled)
    : null;

  switch (node.type) {
    case 'text':
      return (
        <React.Fragment key={key}>
          {processText(node.props.text)}
        </React.Fragment>
      );

    case 'bold':
      return <b key={key}>{children}</b>;

    case 'italic':
      return <i key={key}>{children}</i>;

    case 'strike':
      return <del key={key}>{children}</del>;

    case 'small':
      return (
        <small key={key} style={{ opacity: 0.7 }}>
          {children}
        </small>
      );

    case 'center':
      return (
        <div key={key} style={{ textAlign: 'center' }}>
          {children}
        </div>
      );

    case 'plain':
      return <span key={key}>{children}</span>;

    case 'url':
      return (
        <a
          key={key}
          href={node.props.url}
          target='_blank'
          rel='noopener noreferrer nofollow'
        >
          {node.props.url}
        </a>
      );

    case 'link':
      return (
        <a
          key={key}
          href={node.props.url}
          target='_blank'
          rel='noopener noreferrer nofollow'
        >
          {children}
        </a>
      );

    case 'mention': {
      const host = node.props.host;
      const href = host
        ? `https://${host}/@${node.props.username}`
        : `/@${node.props.acct}`;
      return (
        <span key={key} className='h-card'>
          <a
            href={href}
            className='u-url mention'
            rel='nofollow noopener noreferrer'
            target='_blank'
          >
            @<span>{node.props.username}</span>
            {host ? <span>@{host}</span> : null}
          </a>
        </span>
      );
    }

    case 'hashtag':
      return (
        <a
          key={key}
          href={`/tags/${node.props.hashtag}`}
          className='mention hashtag'
          rel='tag'
        >
          #<span>{node.props.hashtag}</span>
        </a>
      );

    case 'blockCode':
      return (
        <pre key={key}>
          <code>{node.props.code}</code>
        </pre>
      );

    case 'inlineCode':
      return <code key={key}>{node.props.code}</code>;

    case 'quote':
      return <blockquote key={key}>{children}</blockquote>;

    case 'mathInline':
      return (
        <code key={key} className='mfm-math'>
          {node.props.formula}
        </code>
      );

    case 'mathBlock':
      return (
        <pre key={key} className='mfm-math'>
          <code>{node.props.formula}</code>
        </pre>
      );

    case 'search':
      return (
        <span key={key} className='mfm-search'>
          {node.props.query}
        </span>
      );

    case 'unicodeEmoji':
      return <span key={key}>{node.props.emoji}</span>;

    case 'emojiCode':
      return <Emoji key={key} code={`:${node.props.name}:`} />;

    case 'fn':
      return renderMfmFunction(
        node,
        key,
        children,
        allowedTags,
        animationsEnabled,
      );

    default:
      return <span key={key}>{children}</span>;
  }
}

function processText(text: string): React.ReactNode[] {
  const parts = text.split('\n');
  const result: React.ReactNode[] = [];
  parts.forEach((part, i) => {
    if (i > 0) result.push(<br key={`br-${i}`} />);
    if (part) result.push(part);
  });
  return result;
}

const SIMPLE_ANIM_FNS: Record<string, string> = {
  tada: '1s',
  jelly: '1s',
  twitch: '0.5s',
  shake: '0.5s',
  jump: '0.75s',
  bounce: '0.75s',
};

function renderMfmFunction(
  node: mfm.MfmNode & { type: 'fn' },
  key: number,
  children: React.ReactNode[] | null,
  allowedTags: Set<string>,
  animationsEnabled: boolean,
): React.ReactNode {
  const name = node.props.name;
  const args = node.props.args;

  if (!allowedTags.has(name)) {
    return <span key={key}>{children}</span>;
  }

  const useAnim = animationsEnabled;

  if (name in SIMPLE_ANIM_FNS) {
    if (!useAnim) return <span key={key}>{children}</span>;
    const speed = validTime(args.speed) ?? SIMPLE_ANIM_FNS[name] ?? '1s';
    const delay = validTime(args.delay) ?? '0s';
    return (
      <span
        key={key}
        className={`mfm-${name}`}
        style={
          {
            '--mfm-speed': speed,
            '--mfm-delay': delay,
          } as React.CSSProperties
        }
      >
        {children}
      </span>
    );
  }

  switch (name) {
    case 'spin': {
      if (!useAnim) return <span key={key}>{children}</span>;
      const speed = validTime(args.speed) ?? '1.5s';
      const delay = validTime(args.delay) ?? '0s';
      const spinClass =
        'x' in args ? 'mfm-spin-x' : 'y' in args ? 'mfm-spin-y' : 'mfm-spin';
      const direction =
        'left' in args
          ? 'reverse'
          : 'alternate' in args
            ? 'alternate'
            : 'normal';
      return (
        <span
          key={key}
          className={spinClass}
          style={
            {
              '--mfm-speed': speed,
              '--mfm-delay': delay,
              '--mfm-direction': direction,
            } as React.CSSProperties
          }
        >
          {children}
        </span>
      );
    }

    case 'flip': {
      const transform =
        'h' in args && 'v' in args
          ? 'scale(-1, -1)'
          : 'v' in args
            ? 'scaleY(-1)'
            : 'scaleX(-1)';
      return (
        <span key={key} style={{ display: 'inline-block', transform }}>
          {children}
        </span>
      );
    }

    case 'x2':
      return (
        <span key={key} className='mfm-x2'>
          {children}
        </span>
      );

    case 'x3':
      return (
        <span key={key} className='mfm-x3'>
          {children}
        </span>
      );

    case 'x4':
      return (
        <span key={key} className='mfm-x4'>
          {children}
        </span>
      );

    case 'scale': {
      const x = clamp(safeParseFloat(args.x) ?? 1, 0, MFM_MAX_SCALE);
      const y = clamp(safeParseFloat(args.y) ?? 1, 0, MFM_MAX_SCALE);
      return (
        <span
          key={key}
          style={{
            display: 'inline-block',
            transform: `scale(${x}, ${y})`,
            transformOrigin: 'center center',
          }}
        >
          {children}
        </span>
      );
    }

    case 'position': {
      const x = clamp(safeParseFloat(args.x) ?? 0, -100, 100);
      const y = clamp(safeParseFloat(args.y) ?? 0, -100, 100);
      return (
        <span
          key={key}
          style={{
            display: 'inline-block',
            transform: `translateX(${x}em) translateY(${y}em)`,
          }}
        >
          {children}
        </span>
      );
    }

    case 'rotate': {
      const deg = clamp(safeParseFloat(args.deg) ?? 90, -3600, 3600);
      return (
        <span
          key={key}
          style={{
            display: 'inline-block',
            transform: `rotate(${deg}deg)`,
            transformOrigin: 'center center',
          }}
        >
          {children}
        </span>
      );
    }

    case 'fg': {
      const color = validColor(args.color) ?? 'f00';
      return (
        <span
          key={key}
          style={{ color: `#${color}`, overflowWrap: 'anywhere' }}
        >
          {children}
        </span>
      );
    }

    case 'bg': {
      const color = validColor(args.color) ?? 'f00';
      return (
        <span
          key={key}
          style={{ backgroundColor: `#${color}`, overflowWrap: 'anywhere' }}
        >
          {children}
        </span>
      );
    }

    case 'border': {
      const color = validColor(args.color);
      const style =
        typeof args.style === 'string' &&
        MFM_ALLOWED_BORDER_STYLES.has(args.style)
          ? args.style
          : 'solid';
      const width = clamp(safeParseFloat(args.width) ?? 1, 0, 10);
      const radius = clamp(safeParseFloat(args.radius) ?? 0, 0, 100);
      const noclip = 'noclip' in args;
      return (
        <span
          key={key}
          style={{
            display: 'inline-block',
            borderStyle: style,
            borderWidth: `${width}px`,
            borderColor: color ? `#${color}` : undefined,
            borderRadius: `${radius}px`,
            overflow: noclip ? undefined : 'clip',
          }}
        >
          {children}
        </span>
      );
    }

    case 'font': {
      let fontFamily: string | undefined;
      for (const f of MFM_ALLOWED_FONTS) {
        if (f in args) {
          fontFamily = f;
          break;
        }
      }
      if (!fontFamily) return <span key={key}>{children}</span>;
      return (
        <span key={key} style={{ fontFamily }}>
          {children}
        </span>
      );
    }

    case 'blur':
      return (
        <span key={key} className='mfm-blur'>
          {children}
        </span>
      );

    case 'rainbow': {
      if (!useAnim) {
        return (
          <span key={key} className='mfm-rainbow-fallback'>
            {children}
          </span>
        );
      }
      const speed = validTime(args.speed) ?? '1s';
      const delay = validTime(args.delay) ?? '0s';
      return (
        <span
          key={key}
          className='mfm-rainbow'
          style={
            {
              '--mfm-speed': speed,
              '--mfm-delay': delay,
            } as React.CSSProperties
          }
        >
          {children}
        </span>
      );
    }

    case 'sparkle': {
      if (!useAnim) return <span key={key}>{children}</span>;
      return <MfmSparkle key={key}>{children}</MfmSparkle>;
    }

    case 'ruby': {
      if (node.children.length === 0) {
        return <span key={key} />;
      }

      const firstRubyChild = node.children[0];
      if (node.children.length === 1 && firstRubyChild?.type === 'text') {
        const parts = firstRubyChild.props.text.split(' ');
        if (parts.length >= 2) {
          const rubyText = parts.pop() ?? '';
          const baseText = parts.join(' ');
          return (
            <ruby key={key}>
              {baseText}
              <rp>(</rp>
              <rt>{rubyText}</rt>
              <rp>)</rp>
            </ruby>
          );
        }
        return <span key={key}>{firstRubyChild.props.text}</span>;
      }

      const baseChildren = children?.slice(0, -1);
      const lastChild = node.children[node.children.length - 1];
      const rtText = lastChild?.type === 'text' ? lastChild.props.text : '';
      return (
        <ruby key={key}>
          {baseChildren}
          <rp>(</rp>
          <rt>{rtText}</rt>
          <rp>)</rp>
        </ruby>
      );
    }

    case 'unixtime': {
      const firstChild = node.children[0];
      if (firstChild?.type !== 'text') {
        return <span key={key}>{children}</span>;
      }
      const timestamp = parseInt(firstChild.props.text, 10);
      if (isNaN(timestamp)) return <span key={key}>{children}</span>;
      const date = new Date(timestamp * 1000);
      return (
        <time key={key} dateTime={date.toISOString()} className='mfm-unixtime'>
          {date.toLocaleString()}
        </time>
      );
    }

    default:
      return <span key={key}>{children}</span>;
  }
}
