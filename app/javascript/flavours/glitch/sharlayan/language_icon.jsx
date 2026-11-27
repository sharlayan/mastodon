import PropTypes from 'prop-types';

import { languages } from 'flavours/glitch/initial_state';

export const LanguageIcon = ({ language }) => {
  const lang = languages?.find((item) => item[0] === language);
  if (!lang) return null;

  return (
    <span className='text-icon' title={`${lang[2]} (${lang[1]})`} aria-hidden='true'>
      {lang[0].toUpperCase()}
    </span>
  );
};

LanguageIcon.propTypes = {
  language: PropTypes.string.isRequired,
};
