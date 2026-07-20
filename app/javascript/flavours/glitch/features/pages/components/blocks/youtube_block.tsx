import { useMemo } from 'react';

import { useIntl } from 'react-intl';

import classNames from 'classnames';

import type { ApiPageYoutubeBlock } from 'flavours/glitch/api_types/pages';

const videoIdFromUrl = (value: string): string | null => {
  try {
    const url = new URL(value);
    let videoId: string | null = null;

    if (url.protocol !== 'https:') {
      return null;
    }

    switch (url.hostname.toLowerCase()) {
      case 'youtu.be':
        videoId = url.pathname.split('/')[1] ?? null;
        break;
      case 'youtube.com':
      case 'www.youtube.com':
      case 'm.youtube.com':
        if (url.pathname === '/watch') {
          videoId = url.searchParams.get('v');
        } else if (/^\/(?:embed|shorts)\//.test(url.pathname)) {
          videoId = url.pathname.split('/')[2] ?? null;
        }
        break;
    }

    return videoId && /^[\w-]{11}$/u.test(videoId) ? videoId : null;
  } catch {
    return null;
  }
};

export const YoutubeBlock: React.FC<{ block: ApiPageYoutubeBlock }> = ({
  block,
}) => {
  const intl = useIntl();
  const videoId = useMemo(() => videoIdFromUrl(block.url), [block.url]);

  if (!videoId) {
    return null;
  }

  return (
    <div
      className={classNames(
        'page__block',
        'page__block--youtube',
        `page__block--youtube-${block.size ?? 'medium'}`,
      )}
    >
      <iframe
        src={`https://www.youtube-nocookie.com/embed/${videoId}`}
        title={intl.formatMessage({
          id: 'pages.youtube.video',
          defaultMessage: 'YouTube video',
        })}
        allow='accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share'
        allowFullScreen
        loading='lazy'
        referrerPolicy='strict-origin-when-cross-origin'
      />
    </div>
  );
};
