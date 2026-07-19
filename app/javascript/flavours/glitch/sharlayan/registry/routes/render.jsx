import { WrappedRoute } from 'flavours/glitch/features/ui/util/react_router_helpers';

import { sharlayanRouteDescriptors } from '.';

export const renderSharlayanRoutes = (content) =>
  sharlayanRouteDescriptors
    .filter(({ featureGate }) => featureGate())
    .map(({ key, lazyComponent, featureGate, ...route }) => (
      <WrappedRoute
        key={key}
        {...route}
        component={lazyComponent}
        content={content}
      />
    ));
