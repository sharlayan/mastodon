import { openModal } from 'flavours/glitch/actions/modal';
import { browserHistory } from 'flavours/glitch/components/router';
import { layoutFromWindow } from 'flavours/glitch/is_mobile';

const detailedStatusPath = /^(?:\/deck)?\/(?:@[^/]+\/[^/]+|statuses\/[^/]+)\/?$/;
const inlineComposeFeedPath = /^\/(?:home|public(?:\/local)?|lists\/[^/]+|antennas\/[^/]+|conversations|timelines\/direct)\/?$/;

const isSingleColumnInlineComposeRoute = ({ enabled, layout, pathname }) =>
  enabled && layout !== 'multi-column' && (
    detailedStatusPath.test(pathname) || inlineComposeFeedPath.test(pathname)
  );

export const shouldExitDetailedForInlineCompose = ({
  enabled,
  layout,
  pathname,
}) => enabled && layout !== 'multi-column' && detailedStatusPath.test(pathname);

export const shouldOpenInlineComposeReplyModal = ({
  disablePopup,
  ...options
}) => isSingleColumnInlineComposeRoute(options) && !disablePopup;

const scrollToTopAfterNavigation = () => {
  requestAnimationFrame(() => {
    requestAnimationFrame(() => {
      if (document.scrollingElement) {
        document.scrollingElement.scrollTop = 0;
      }
    });
  });
};

export const handleReplyForInlineCompose = (dispatch, getState) => {
  const options = {
    disablePopup: getState().getIn(['local_settings', 'disable_inline_compose_reply_modal'], false),
    enabled: getState().getIn(['local_settings', 'inline_compose_timelines'], false),
    layout: layoutFromWindow(),
    pathname: browserHistory.location.pathname,
  };

  if (shouldOpenInlineComposeReplyModal(options)) {
    dispatch(openModal({
      modalType: 'INLINE_COMPOSE',
      modalProps: {},
    }));
    return true;
  }

  if (!shouldExitDetailedForInlineCompose(options)) {
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
