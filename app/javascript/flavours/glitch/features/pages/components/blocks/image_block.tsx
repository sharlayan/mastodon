import { useCallback } from 'react';

import type {
  ApiPageImageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';

import type { PageMediaOpenHandler } from './index';

export const ImageBlock: React.FC<{
  block: ApiPageImageBlock;
  page: ApiPageJSON;
  onOpenMedia: PageMediaOpenHandler;
}> = ({ block, page, onOpenMedia }) => {
  const media = page.attached_media.find((item) => item.id === block.fileId);
  const handleOpenMedia = useCallback(() => {
    onOpenMedia(`block:${block.id}`);
  }, [block.id, onOpenMedia]);

  if (!media) {
    return null;
  }

  const description = media.description ?? '';

  return (
    <div className='page__block page__block--image'>
      <button
        type='button'
        className='page__media-button'
        onClick={handleOpenMedia}
      >
        {media.type === 'gifv' ? (
          <video
            src={media.url}
            aria-label={description}
            title={description}
            autoPlay
            loop
            muted
            playsInline
          />
        ) : (
          <img src={media.url} alt={description} title={description} />
        )}
      </button>
    </div>
  );
};
