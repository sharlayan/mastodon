import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import { matchPath, useLocation } from 'react-router-dom';

import classNames from 'classnames';

import AddIcon from '@/material-icons/400-24px/add.svg?react';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import PeopleIcon from '@/material-icons/400-24px/group.svg?react';
import HomeIcon from '@/material-icons/400-24px/home-fill.svg?react';
import ListAltIcon from '@/material-icons/400-24px/list_alt.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import RadarIcon from '@/material-icons/400-24px/radar.svg?react';
import { fetchAntennas } from 'flavours/glitch/actions/antennas';
import { mountCompose, unmountCompose } from 'flavours/glitch/actions/compose';
import { apiRequestPut } from 'flavours/glitch/api';
import { fetchLists } from 'flavours/glitch/actions/lists_typed';
import { Icon } from 'flavours/glitch/components/icon';
import { TabList, TabLink } from 'flavours/glitch/components/tab_list';
import ComposeFormContainer from 'flavours/glitch/features/compose/containers/compose_form_container';
import { me, antennaEnabled, federatedTimelineEnabled, inlineComposeTabs, localTimelineEnabled } from 'flavours/glitch/initial_state';
import { getOrderedLists } from 'flavours/glitch/selectors/lists';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

const messages = defineMessages({
  home: { id: 'tabs_bar.home', defaultMessage: 'Home' },
  local: { id: 'navigation_bar.community_timeline', defaultMessage: 'Local' },
  federated: { id: 'navigation_bar.public_timeline', defaultMessage: 'Federated' },
  add: { id: 'inline_compose.add_tab', defaultMessage: 'Add a feed' },
  remove: { id: 'inline_compose.remove_tab', defaultMessage: 'Remove tab' },
  lists: { id: 'inline_compose.lists', defaultMessage: 'Lists' },
  antennas: { id: 'inline_compose.antennas', defaultMessage: 'Antennas' },
});

export const InlineComposeShell = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const location = useLocation();

  const enabled = useAppSelector((state) => state.local_settings.get('inline_compose_timelines', false)) && !!me;
  const expandOnClick = useAppSelector((state) => state.local_settings.get('inline_compose_expand_on_click', false));
  const hasComposeContents = useAppSelector((state) => {
    const compose = state.get('compose');

    return compose.get('text').trim().length > 0
      || compose.get('spoiler_text').trim().length > 0
      || compose.get('in_reply_to') !== null
      || compose.get('id') !== null
      || compose.get('poll') !== null
      || compose.get('quoted_status_id') !== null
      || compose.get('media_attachments').size > 0;
  });
  const isSubmitting = useAppSelector((state) => state.getIn(['compose', 'is_submitting']));
  const lists = useAppSelector((state) => getOrderedLists(state));
  const antennas = useAppSelector((state) => state.get('antennas'));

  const [menuOpen, setMenuOpen] = useState(false);
  const [savedTabList, setSavedTabList] = useState(inlineComposeTabs);
  const [composeExpanded, setComposeExpanded] = useState(false);
  const menuRef = useRef(null);
  const wasSubmitting = useRef(isSubmitting);

  const tabs = useMemo(() => {
    const base = [{ to: '/home', label: intl.formatMessage(messages.home), icon: 'home', iconComponent: HomeIcon }];

    if (localTimelineEnabled) {
      base.push({ to: '/public/local', label: intl.formatMessage(messages.local), icon: 'users', iconComponent: PeopleIcon });
    }
    if (federatedTimelineEnabled) {
      base.push({ to: '/public', label: intl.formatMessage(messages.federated), icon: 'globe', iconComponent: PublicIcon });
    }

    const dynamic = savedTabList.map((tab) => {
      if (tab.type === 'list') {
        const list = lists.find((item) => String(item.id) === String(tab.id));
        return { to: `/lists/${tab.id}`, label: list ? list.title : tab.id, icon: 'list-ul', iconComponent: ListAltIcon, tab, removable: true };
      }

      const antenna = antennas ? antennas.get(String(tab.id)) : null;
      return { to: `/antennas/${tab.id}`, label: antenna ? antenna.get('title') : tab.id, icon: 'radar', iconComponent: RadarIcon, tab, removable: true };
    });

    return base.concat(dynamic);
  }, [intl, savedTabList, lists, antennas]);

  const isFeedRoute = useMemo(
    () => tabs.some((tab) => matchPath(location.pathname, { path: tab.to, exact: true }))
      || !!matchPath(location.pathname, { path: '/lists/:id', exact: true })
      || !!matchPath(location.pathname, { path: '/antennas/:id', exact: true })
      || !!matchPath(location.pathname, { path: ['/conversations', '/timelines/direct'], exact: true }),
    [tabs, location.pathname],
  );

  const active = enabled && isFeedRoute;

  useEffect(() => {
    if (!expandOnClick || hasComposeContents) {
      setComposeExpanded(true);
    }
  }, [expandOnClick, hasComposeContents]);

  useEffect(() => {
    if (expandOnClick && wasSubmitting.current && !isSubmitting && !hasComposeContents) {
      setComposeExpanded(false);
    }

    wasSubmitting.current = isSubmitting;
  }, [expandOnClick, hasComposeContents, isSubmitting]);

  useEffect(() => {
    if (!active) {
      return undefined;
    }

    dispatch(mountCompose());
    document.documentElement.classList.add('inline-compose-mode');

    return () => {
      dispatch(unmountCompose());
      document.documentElement.classList.remove('inline-compose-mode');
    };
  }, [dispatch, active]);

  useEffect(() => {
    if (!menuOpen) {
      return undefined;
    }

    const handleClick = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [menuOpen]);

  useEffect(() => {
    if (!enabled) {
      return;
    }

    dispatch(fetchLists());

    if (antennaEnabled) {
      dispatch(fetchAntennas());
    }
  }, [dispatch, enabled]);

  const toggleMenu = useCallback(() => setMenuOpen((open) => !open), []);

  const handleComposeBlur = useCallback((event) => {
    if (expandOnClick && !hasComposeContents && !event.currentTarget.contains(event.relatedTarget)) {
      setComposeExpanded(false);
    }
  }, [expandOnClick, hasComposeContents]);

  const addTab = useCallback((type, id) => {
    const next = savedTabList.filter((tab) => !(tab.type === type && String(tab.id) === String(id)));
    next.push({ type, id: String(id) });
    setSavedTabList(next);
    void apiRequestPut('v1/inline_compose_tabs', { tabs: next }).catch(() => undefined);
    setMenuOpen(false);
  }, [savedTabList]);

  const removeTab = useCallback((tab) => {
    const next = savedTabList.filter((item) => !(item.type === tab.type && String(item.id) === String(tab.id)));
    setSavedTabList(next);
    void apiRequestPut('v1/inline_compose_tabs', { tabs: next }).catch(() => undefined);
  }, [savedTabList]);

  const availableLists = useMemo(
    () => lists.filter((list) => !savedTabList.some((tab) => tab.type === 'list' && String(tab.id) === String(list.id))),
    [lists, savedTabList],
  );

  const availableAntennas = useMemo(() => {
    if (!antennaEnabled || !antennas) {
      return [];
    }

    return antennas
      .valueSeq()
      .filter((antenna) => !!antenna)
      .filter((antenna) => !savedTabList.some((tab) => tab.type === 'antenna' && String(tab.id) === String(antenna.get('id'))))
      .toArray();
  }, [antennas, savedTabList]);

  if (!active) {
    return null;
  }

  const hasMenuItems = availableLists.length > 0 || availableAntennas.length > 0;

  return (
    <div className='inline-compose-shell'>
      <div className='inline-compose-shell__bar'>
        <TabList plain className='inline-compose-shell__tabs'>
          {tabs.map((tab) => (
            <TabLink key={tab.to} to={tab.to} exact className='inline-compose-shell__tab'>
              <Icon id={tab.icon} icon={tab.iconComponent} />
              <span className='inline-compose-shell__tab-label'>{tab.label}</span>
              {tab.removable && (
                <span
                  role='button'
                  tabIndex={0}
                  className='inline-compose-shell__tab-remove'
                  aria-label={intl.formatMessage(messages.remove)}
                  onClick={(e) => { e.preventDefault(); e.stopPropagation(); removeTab(tab.tab); }}
                >
                  <Icon id='times' icon={CloseIcon} />
                </span>
              )}
            </TabLink>
          ))}
        </TabList>

        <div className='inline-compose-shell__add' ref={menuRef}>
          <button
            type='button'
            className='inline-compose-shell__add-button'
            aria-label={intl.formatMessage(messages.add)}
            title={intl.formatMessage(messages.add)}
            onClick={toggleMenu}
          >
            <Icon id='plus' icon={AddIcon} />
          </button>

          {menuOpen && hasMenuItems && (
            <div className='inline-compose-shell__menu'>
              {availableLists.length > 0 && (
                <>
                  <div className='inline-compose-shell__menu-heading'>{intl.formatMessage(messages.lists)}</div>
                  {availableLists.map((list) => (
                    <button
                      type='button'
                      key={`list-${list.id}`}
                      className='inline-compose-shell__menu-item'
                      onClick={() => addTab('list', list.id)}
                    >
                      <Icon id='list-ul' icon={ListAltIcon} />
                      {list.title}
                    </button>
                  ))}
                </>
              )}

              {availableAntennas.length > 0 && (
                <>
                  <div className='inline-compose-shell__menu-heading'>{intl.formatMessage(messages.antennas)}</div>
                  {availableAntennas.map((antenna) => (
                    <button
                      type='button'
                      key={`antenna-${antenna.get('id')}`}
                      className='inline-compose-shell__menu-item'
                      onClick={() => addTab('antenna', antenna.get('id'))}
                    >
                      <Icon id='radar' icon={RadarIcon} />
                      {antenna.get('title')}
                    </button>
                  ))}
                </>
              )}
            </div>
          )}
        </div>
      </div>

      <div
        className={classNames('inline-compose-form', { 'inline-compose-form--collapsed': expandOnClick && !composeExpanded })}
        onClick={() => setComposeExpanded(true)}
        onBlurCapture={handleComposeBlur}
        onFocusCapture={() => setComposeExpanded(true)}
      >
        <ComposeFormContainer isInline withoutNavigation />
      </div>
    </div>
  );
};
