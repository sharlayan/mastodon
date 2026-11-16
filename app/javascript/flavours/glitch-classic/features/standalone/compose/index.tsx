import { lazy, Suspense, useEffect } from 'react';

import { AlertsController } from '@/flavours/glitch-classic/components/alerts_controller';
import { LoadingIndicator } from '@/flavours/glitch-classic/components/loading_indicator';
import ComposeFormContainer from '@/flavours/glitch-classic/features/compose/containers/compose_form_container';
import LoadingBarContainer from '@/flavours/glitch-classic/features/ui/containers/loading_bar_container';
import ModalContainer from '@/flavours/glitch-classic/features/ui/containers/modal_container';
import { isRedesignEnabled } from '@/flavours/glitch-classic/utils/environment';

const ComposeLazyForm = lazy(() =>
  import('@/flavours/glitch-classic/features/compose/redesign/index').then(
    ({ RedesignComposeForm }) => ({
      default: RedesignComposeForm,
    }),
  ),
);

export const Compose: React.FC = () => {
  return (
    <>
      {isRedesignEnabled() ? (
        <RedesignCompose />
      ) : (
        <ComposeFormContainer autoFocus withoutNavigation redirectOnSuccess />
      )}
      <AlertsController />
      <ModalContainer />
      <LoadingBarContainer className='loading-bar' />
    </>
  );
};

const RedesignCompose: React.FC = () => {
  useEffect(() => {
    document.documentElement.dataset.redesign = 'true';
    return () => {
      document.documentElement.dataset.redesign = 'false';
    };
  }, []);

  return (
    <Suspense fallback={<LoadingIndicator />}>
      <ComposeLazyForm autoFocus headless redirectOnSuccess />
    </Suspense>
  );
};

// eslint-disable-next-line import/no-default-export
export default Compose;
