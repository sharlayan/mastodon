import { useLayoutEffect, useRef } from 'react';

import PropTypes from 'prop-types';

export const getOverflowHighlightText = (value, overflowStart) => {
  if (overflowStart < 0 || overflowStart >= value.length) {
    return null;
  }

  return {
    before: value.slice(0, overflowStart),
    overflow: value.slice(overflowStart),
  };
};

export const SharlayanOverflowHighlight = ({ overflowStart, textareaElement, value }) => {
  const highlightsRef = useRef(null);
  const highlightsContentRef = useRef(null);

  useLayoutEffect(() => {
    if (!textareaElement) {
      return undefined;
    }

    const syncScroll = () => {
      const content = highlightsContentRef.current;

      if (content) {
        content.style.transform = `translateY(${-textareaElement.scrollTop}px)`;
      }
    };

    const syncMetrics = () => {
      const highlights = highlightsRef.current;

      if (!highlights) {
        return;
      }

      highlights.style.width = `${textareaElement.clientWidth}px`;
      highlights.style.height = `${textareaElement.clientHeight}px`;
      syncScroll();
    };

    syncMetrics();

    const observer = new ResizeObserver(syncMetrics);
    observer.observe(textareaElement);
    textareaElement.addEventListener('scroll', syncScroll, { passive: true });

    return () => {
      observer.disconnect();
      textareaElement.removeEventListener('scroll', syncScroll);
    };
  }, [textareaElement, value, overflowStart]);

  const text = getOverflowHighlightText(value, overflowStart);

  if (!text) {
    return null;
  }

  return (
    <div className='autosuggest-textarea__highlights' ref={highlightsRef} aria-hidden='true'>
      <div className='autosuggest-textarea__highlights__content' ref={highlightsContentRef} dir='auto'>
        {text.before}
        <mark className='autosuggest-textarea__highlights__over'>{text.overflow}</mark>
      </div>
    </div>
  );
};

SharlayanOverflowHighlight.propTypes = {
  overflowStart: PropTypes.number.isRequired,
  textareaElement: PropTypes.object,
  value: PropTypes.string.isRequired,
};
