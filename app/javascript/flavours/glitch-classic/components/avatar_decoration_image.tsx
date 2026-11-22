import { useCallback, useRef, useState } from 'react';
import type { CSSProperties, FC, SyntheticEvent } from 'react';

import { useAppSelector } from '@/flavours/glitch-classic/store';

import { RetryingImage } from './retrying_image';

const MIN_FRAME_SIZE = 64;
const FRAME_SCALE = 2;
const HIDDEN_LOADER: CSSProperties = {
  position: 'absolute',
  width: 1,
  height: 1,
  visibility: 'hidden',
  pointerEvents: 'none',
};

export const useDecorationAutoplayDisabled = () =>
  useAppSelector(
    (state) =>
      state.local_settings.getIn([
        'media',
        'no_autoplay_avatar_decorations',
      ]) === true,
  );

interface ImageProps {
  className?: string;
  style?: CSSProperties;
}

const FirstFrameDecoration: FC<
  ImageProps & { src: string; playing: boolean }
> = ({ src, playing, className, style }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [captured, setCaptured] = useState(false);
  const [unsupported, setUnsupported] = useState(false);
  const [imageLoaded, setImageLoaded] = useState(false);

  if (!playing && captured && imageLoaded) setImageLoaded(false);

  const handleLoad = useCallback(
    (event: SyntheticEvent<HTMLImageElement>) => {
      setImageLoaded(true);
      if (captured) return;

      const image = event.currentTarget;
      const canvas = canvasRef.current;
      const context = canvas?.getContext('2d');
      const longest = Math.max(image.naturalWidth, image.naturalHeight);
      if (!canvas || !context || longest === 0) {
        setUnsupported(true);
        return;
      }

      const displayed = Math.max(
        canvas.clientWidth,
        canvas.clientHeight,
        MIN_FRAME_SIZE,
      );
      const wanted = Math.ceil(
        displayed * (window.devicePixelRatio || 1) * FRAME_SCALE,
      );
      const ratio = Math.min(1, wanted / longest);
      canvas.width = Math.max(1, Math.round(image.naturalWidth * ratio));
      canvas.height = Math.max(1, Math.round(image.naturalHeight * ratio));
      context.drawImage(image, 0, 0, canvas.width, canvas.height);
      setCaptured(true);
    },
    [captured],
  );

  if (unsupported)
    return (
      <RetryingImage className={className} src={src} alt='' style={style} />
    );

  const imageVisible = playing && imageLoaded;

  return (
    <>
      <canvas
        ref={canvasRef}
        aria-hidden='true'
        className={className}
        style={{
          ...style,
          display: imageVisible ? 'none' : undefined,
          visibility: captured ? undefined : 'hidden',
        }}
      />
      {(playing || !captured) && (
        <RetryingImage
          className={className}
          src={src}
          alt=''
          onLoad={handleLoad}
          style={imageVisible ? style : HIDDEN_LOADER}
        />
      )}
    </>
  );
};

export const FrozenDecorationImage: FC<
  ImageProps & { url: string; staticUrl: string; playing: boolean }
> = ({ url, staticUrl, playing, className, style }) => {
  if (staticUrl !== url)
    return (
      <RetryingImage
        className={className}
        src={playing ? url : staticUrl}
        alt=''
        style={style}
      />
    );

  return (
    <FirstFrameDecoration
      key={url}
      src={url}
      playing={playing}
      className={className}
      style={style}
    />
  );
};
