import { useCallback } from 'react';

import classNames from 'classnames';

import type {
  ApiPageImageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';
import { useVisibility } from 'flavours/glitch/hooks/useVisibility';

import type { PageMediaOpenHandler } from './index';

const observerOptions = { rootMargin: '400px 0px' };

export const ImageBlock: React.FC<{
  block: ApiPageImageBlock;
  page: ApiPageJSON;
  onOpenMedia: PageMediaOpenHandler;
}> = ({ block, page, onOpenMedia }) => {
  const media = page.attached_media.find((item) => item.id === block.fileId);
  const { hasIntersected, observedRef } = useVisibility({ observerOptions });
  const handleOpenMedia = useCallback(() => {
    onOpenMedia(`block:${block.id}`);
  }, [block.id, onOpenMedia]);

  if (!media) {
    return null;
  }

  const description = media.description ?? '';
  const dimensions =
    media.type === 'image' || media.type === 'gifv'
      ? media.meta.original
      : null;
  const mediaStyle =
    dimensions?.width && dimensions.height
      ? {
          aspectRatio: `${dimensions.width} / ${dimensions.height}`,
          width: block.noUpscale ? dimensions.width : undefined,
        }
      : undefined;

  return (
    <div
      ref={observedRef}
      className={classNames('page__block', 'page__block--image', {
        'page__block--image-no-upscale': block.noUpscale,
      })}
      style={mediaStyle}
    >
      <button
        type='button'
        className='page__media-button'
        onClick={handleOpenMedia}
      >
        {media.type === 'gifv' ? (
          <video
            src={hasIntersected ? media.url : undefined}
            aria-label={description}
            title={description}
            autoPlay={hasIntersected}
            loop
            muted
            playsInline
            preload='none'
          />
        ) : (
          <img
            src={media.url}
            alt={description}
            title={description}
            width={dimensions?.width}
            height={dimensions?.height}
            loading='lazy'
            decoding='async'
          />
        )}
      </button>
    </div>
  );
};
