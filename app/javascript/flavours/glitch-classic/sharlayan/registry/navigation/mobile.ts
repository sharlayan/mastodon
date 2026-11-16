import { useIdentity } from '@/flavours/glitch-classic/identity_context';
import {
  localLiveFeedAccess,
  localTimelineEnabled,
} from '@/flavours/glitch-classic/initial_state';
import { canViewFeed } from '@/flavours/glitch-classic/permissions';
import { useAppSelector } from '@/flavours/glitch-classic/store';

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
