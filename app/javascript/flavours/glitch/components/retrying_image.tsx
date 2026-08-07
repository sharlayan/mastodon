import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

const RETRY_DELAYS = [5_000, 15_000, 30_000];

const withRetryToken = (src: string, token: number) => {
  if (token === 0) return src;

  const hashIndex = src.indexOf('#');
  const base = hashIndex === -1 ? src : src.slice(0, hashIndex);
  const hash = hashIndex === -1 ? '' : src.slice(hashIndex);
  const separator = base.includes('?') ? '&' : '?';

  return `${base}${separator}_sharlayan_retry=${token}${hash}`;
};

type Props = Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'alt' | 'src'> & {
  alt: string;
  src: string;
};

const RetryingImageContent: React.FC<Props> = ({
  alt,
  src,
  onError,
  onLoad,
  ...props
}) => {
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [retryToken, setRetryToken] = useState(0);
  const retryTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const retry = useCallback(() => {
    setFailed(false);
    setAttempt((current) => current + 1);
    setRetryToken(Date.now());
  }, []);

  useEffect(
    () => () => {
      if (retryTimer.current !== null) clearTimeout(retryTimer.current);
    },
    [],
  );

  useEffect(() => {
    if (!failed || attempt < RETRY_DELAYS.length) return undefined;

    const handleFocus = () => {
      retry();
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') retry();
    };

    window.addEventListener('focus', handleFocus);
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      window.removeEventListener('focus', handleFocus);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [attempt, failed, retry]);

  const handleError = useCallback(
    (event: React.SyntheticEvent<HTMLImageElement>) => {
      setFailed(true);
      onError?.(event);

      const delay = RETRY_DELAYS[attempt];
      if (delay !== undefined) retryTimer.current = setTimeout(retry, delay);
    },
    [attempt, onError, retry],
  );

  const handleLoad = useCallback(
    (event: React.SyntheticEvent<HTMLImageElement>) => {
      if (retryTimer.current !== null) {
        clearTimeout(retryTimer.current);
        retryTimer.current = null;
      }
      setFailed(false);
      onLoad?.(event);
    },
    [onLoad],
  );

  const retrySrc = useMemo(
    () => withRetryToken(src, retryToken),
    [retryToken, src],
  );

  if (failed) return null;

  return (
    <img
      {...props}
      src={retrySrc}
      alt={alt}
      onLoad={handleLoad}
      onError={handleError}
    />
  );
};

export const RetryingImage: React.FC<Props> = (props) => (
  <RetryingImageContent key={props.src} {...props} />
);
