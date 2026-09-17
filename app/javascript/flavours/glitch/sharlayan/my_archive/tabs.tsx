import { FormattedMessage } from 'react-intl';

import { NavLink } from 'react-router-dom';

import { clipsEnabled } from 'flavours/glitch/initial_state';
import { useAppSelector } from 'flavours/glitch/store';

export const MyArchiveTabs: React.FC = () => {
  const enabled = useAppSelector(
    (state) => state.local_settings.get('use_my_archive', false) as boolean,
  );

  if (!enabled) {
    return null;
  }

  return (
    <div className='account__section-headline my-archive__tabs'>
      <NavLink exact replace to='/favourites'>
        <FormattedMessage id='column.favourites' defaultMessage='Favorites' />
      </NavLink>
      <NavLink exact replace to='/bookmarks'>
        <FormattedMessage id='column.bookmarks' defaultMessage='Bookmarks' />
      </NavLink>
      <NavLink exact replace to='/reactions'>
        <FormattedMessage id='column.reactions' defaultMessage='Reactions' />
      </NavLink>
      {clipsEnabled && (
        <NavLink exact replace to='/clips'>
          <FormattedMessage id='column.clips' defaultMessage='Clips' />
        </NavLink>
      )}
    </div>
  );
};
