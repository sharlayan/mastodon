import type {
  ApiPageImageBlock,
  ApiPageJSON,
} from 'flavours/glitch/api_types/pages';

export const ImageBlock: React.FC<{
  block: ApiPageImageBlock;
  page: ApiPageJSON;
}> = ({ block, page }) => {
  const media = page.attached_media.find((item) => item.id === block.fileId);

  if (!media) {
    return null;
  }

  const description = media.description ?? '';

  return (
    <div className='page__block page__block--image'>
      <a href={media.url} target='_blank' rel='noopener noreferrer'>
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
      </a>
    </div>
  );
};
