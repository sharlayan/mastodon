import { useIdentity } from '@/flavours/glitch/identity_context';
import {
  localLiveFeedAccess,
  localTimelineEnabled,
} from '@/flavours/glitch/initial_state';
import { canViewFeed } from '@/flavours/glitch/permissions';
import { useAppSelector } from '@/flavours/glitch/store';

export const useMobileLocalTimeline = () => {
  const { signedIn, permissions } = useIdentity();
  const enabled = useAppSelector(
    (state) =>
      state.local_settings.getIn(
        ['navigation_panel', 'mobile_local_timeline'],
        false,
      ) === true,
  );

  return (
    enabled &&
    signedIn &&
    localTimelineEnabled &&
    canViewFeed(signedIn, permissions, localLiveFeedAccess)
  );
};
