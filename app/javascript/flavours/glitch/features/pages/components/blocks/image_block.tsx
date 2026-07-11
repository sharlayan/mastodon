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

  return (
    <div className='page__block page__block--image'>
      <a href={media.url} target='_blank' rel='noopener noreferrer'>
        <img
          src={media.preview_url || media.url}
          alt={media.description ?? ''}
          title={media.description ?? ''}
        />
      </a>
    </div>
  );
};
