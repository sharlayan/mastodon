import { useEffect } from 'react';

import PropTypes from 'prop-types';

import { mountCompose, unmountCompose } from 'flavours/glitch/actions/compose';
import ComposeFormContainer from 'flavours/glitch/features/compose/containers/compose_form_container';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

export const InlineComposeForm = ({ multiColumn }) => {
  const dispatch = useAppDispatch();
  const enabled = useAppSelector((state) => state.local_settings.get('inline_compose_timelines', false));
  const active = enabled && !multiColumn;

  useEffect(() => {
    if (!active) {
      return undefined;
    }

    dispatch(mountCompose());

    return () => {
      dispatch(unmountCompose());
    };
  }, [dispatch, active]);

  if (!active) {
    return null;
  }

  return (
    <div className='inline-compose-form'>
      <ComposeFormContainer />
    </div>
  );
};

InlineComposeForm.propTypes = {
  multiColumn: PropTypes.bool,
};
