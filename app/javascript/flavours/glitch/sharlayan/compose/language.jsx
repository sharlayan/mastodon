import PropTypes from 'prop-types';
import { useSelector } from 'react-redux';

import { shouldShowComposeLanguage } from './calculations';

export const SharlayanComposeLanguage = ({ children }) => {
  const hideComposeLanguage = useSelector((state) => state.getIn(['local_settings', 'hide_compose_language']));

  return shouldShowComposeLanguage(hideComposeLanguage) ? children : null;
};

SharlayanComposeLanguage.propTypes = {
  children: PropTypes.node,
};
