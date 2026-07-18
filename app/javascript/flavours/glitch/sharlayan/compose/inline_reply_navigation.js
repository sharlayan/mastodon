import { browserHistory } from 'flavours/glitch/components/router';
import { layoutFromWindow } from 'flavours/glitch/is_mobile';

const detailedStatusPath = /^(?:\/deck)?\/(?:@[^/]+\/[^/]+|statuses\/[^/]+)\/?$/;

export const shouldExitDetailedForInlineCompose = ({
  enabled,
  layout,
  pathname,
}) => enabled && layout !== 'multi-column' && detailedStatusPath.test(pathname);

const scrollToTopAfterNavigation = () => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (document.scrollingElement) {
        document.scrollingElement.scrollTop = 0;
      }
    });
  });
};

export const exitDetailedForInlineCompose = (getState) => {
  if (!shouldExitDetailedForInlineCompose({
    enabled: getState().getIn(['local_settings', 'inline_compose_timelines'], false),
    layout: layoutFromWindow(),
    pathname: browserHistory.location.pathname,
  })) {
    return false;
  }

  const unlisten = browserHistory.listen(() => {
    unlisten();
    scrollToTopAfterNavigation();
  });

  if (browserHistory.location.state?.fromMastodon) {
    browserHistory.goBack();
  } else {
    browserHistory.push('/', { focusTarget: false });
  }

  return true;
};
