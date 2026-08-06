import PropTypes from 'prop-types';

import { defineMessages, FormattedDate, FormattedMessage } from 'react-intl';

import { connect } from 'react-redux';

import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import CloudSyncIcon from '@/material-icons/400-24px/cloud_sync.svg?react';
import ListIcon from '@/material-icons/400-24px/list.svg?react';
import SettingsIcon from '@/material-icons/400-24px/settings-fill.svg?react';
import TuneIcon from '@/material-icons/400-24px/tune.svg?react';
import UnfoldLessIcon from '@/material-icons/400-24px/unfold_less.svg?react';
import { Button } from '@/flavours/glitch/components/button';
import { Icon } from '@/flavours/glitch/components/icon';
import { injectIntl } from '@/flavours/glitch/components/intl';
import { fetchLocalSettingsFromServer, pushLocalSettingsToServer } from 'flavours/glitch/actions/local_settings';
import { me } from 'flavours/glitch/initial_state';
import { preferencesLink } from 'flavours/glitch/utils/backend_links';

import NavigationPanelSettings from '../../features/local_settings/page/navigation_panel';
import StatusActionBarSettings from '../../features/local_settings/page/status_action_bar';
import LocalSettingsPageItem from '../../features/local_settings/page/item';
import QuickPreferences from '../../features/local_settings/page/quick_preferences';
import CollapsedStatusesSettings from '../../features/local_settings/page/collapsed_statuses';

const messages = defineMessages({
  title: { id: 'navigation_bar.app_settings', defaultMessage: 'App settings' },
  quick_preferences: { id: 'settings.quick_preferences', defaultMessage: 'Quick preferences' },
  navigation_panel: { id: 'settings.navigation_panel', defaultMessage: 'Navigation panel' },
  status_action_bar: { id: 'settings.status_action_bar', defaultMessage: 'Post action bar' },
  sync: { id: 'settings.sync', defaultMessage: 'Server sync' },
  preferences: { id: 'settings.preferences', defaultMessage: 'Preferences' },
  close: { id: 'settings.close', defaultMessage: 'Close' },
});

const SyncSettingsPage = ({ settings, onChange, onSyncFromServer, onSyncToServer }) => (
  <div className='glitch local-settings__page sync'>
    <h1><FormattedMessage id='settings.sync' defaultMessage='Server sync' /></h1>
    <p className='hint'>
      <FormattedMessage id='settings.sync.hint' defaultMessage='App settings are normally stored only in this browser. Enable server sync to manually save them to your account and load them on another device.' />
    </p>
    <LocalSettingsPageItem settings={settings} item={['sync_to_server']} id='mastodon-settings--sync_to_server' onChange={onChange} disabled={!me}>
      <FormattedMessage id='settings.sync.enable' defaultMessage='Enable server sync' />
    </LocalSettingsPageItem>
    <div className='local-settings__page__sync-actions'>
      <Button onClick={onSyncToServer} disabled={!me || !settings.get('sync_to_server')}><FormattedMessage id='settings.sync.save' defaultMessage='Save to server' /></Button>
      <Button onClick={onSyncFromServer} disabled={!me || !settings.get('sync_to_server')}><FormattedMessage id='settings.sync.load' defaultMessage='Load from server' /></Button>
    </div>
    {settings.get('synced_at') && (
      <p className='hint local-settings__page__sync-status'>
        <FormattedMessage id='settings.sync.last_synced' defaultMessage='Last saved: {date}' values={{ date: <FormattedDate value={settings.get('synced_at')} year='numeric' month='short' day='2-digit' hour='2-digit' minute='2-digit' /> }} />
      </p>
    )}
  </div>
);

SyncSettingsPage.propTypes = {
  settings: PropTypes.object.isRequired,
  onChange: PropTypes.func.isRequired,
  onSyncFromServer: PropTypes.func.isRequired,
  onSyncToServer: PropTypes.func.isRequired,
};

const ConnectedSyncSettingsPage = connect(null, dispatch => ({
  onSyncToServer: () => dispatch(pushLocalSettingsToServer()),
  onSyncFromServer: () => dispatch(fetchLocalSettingsFromServer()),
}))(SyncSettingsPage);

export const getSharlayanLocalSettingsPage = (index, pages) => {
  if (index === 1) return QuickPreferences;
  if (index === 5) return ConnectedSyncSettingsPage;
  if (index === 6) return NavigationPanelSettings;
  if (index === 7) return StatusActionBarSettings;
  if (index === 8) return CollapsedStatusesSettings;

  return pages[[0, null, 1, 2, 3][index]];
};

const localSettingsSlots = {
  'general-after-rewrite': [
    {
      setting: ['content_font_size'],
      id: 'mastodon-settings--content_font_size',
      message: { id: 'settings.content_font_size', defaultMessage: 'Post text size' },
      hint: { id: 'settings.content_font_size.hint', defaultMessage: 'Adjust the font size of post bodies only. Other interface text is not affected' },
      options: [
        { value: 'medium', message: { id: 'settings.content_font_size.medium', defaultMessage: 'Medium' } },
        { value: 'large', message: { id: 'settings.content_font_size.large', defaultMessage: 'Large' } },
        { value: 'x_large', message: { id: 'settings.content_font_size.x_large', defaultMessage: 'Extra large' } },
        { value: 'xx_large', message: { id: 'settings.content_font_size.xx_large', defaultMessage: 'Huge' } },
      ],
    },
    {
      setting: ['sensitive_emoji_display'],
      id: 'mastodon-settings--sensitive_emoji_display',
      message: { id: 'settings.sensitive_emoji_display', defaultMessage: 'Sensitive custom emojis' },
      hint: { id: 'settings.sensitive_emoji_display.hint', defaultMessage: 'Choose how custom emojis marked as sensitive by server moderators are displayed' },
      options: [
        { value: 'show', message: { id: 'settings.sensitive_emoji_display.show', defaultMessage: 'Show normally' } },
        { value: 'grayscale', message: { id: 'settings.sensitive_emoji_display.grayscale', defaultMessage: 'Show in grayscale' } },
        { value: 'hide', message: { id: 'settings.sensitive_emoji_display.hide', defaultMessage: 'Hide' } },
      ],
    },
    { setting: ['show_follow_list_bio'], id: 'mastodon-settings--show_follow_list_bio', message: { id: 'settings.show_follow_list_bio', defaultMessage: 'Show bio and follow message in follow lists' }, hint: { id: 'settings.show_follow_list_bio.hint', defaultMessage: 'Display a short bio (up to 100 characters) and follow message under accounts in followers and following lists' } },
    { setting: ['show_others_online_status'], id: 'mastodon-settings--show_others_online_status', message: { id: 'settings.show_others_online_status', defaultMessage: "Show other people's online status" }, hint: { id: 'settings.show_others_online_status.hint', defaultMessage: 'Display an online, recently active, or offline indicator on the avatars of users who share their status' } },
    { setting: ['show_instance_info'], id: 'mastodon-settings--show_instance_info', message: { id: 'settings.show_instance_info', defaultMessage: 'Show instance information on posts' }, hint: { id: 'settings.show_instance_info.hint', defaultMessage: 'Display the instance name, theme color, and favicon on posts' } },
    { setting: ['show_instance_info_local'], id: 'mastodon-settings--show_instance_info_local', message: { id: 'settings.show_instance_info_local', defaultMessage: 'Also show instance information on posts from this server' }, hint: { id: 'settings.show_instance_info_local.hint', defaultMessage: 'Posts from your own server hide the badge unless this is enabled' }, dependsOn: ['show_instance_info'] },
  ],
  'general-status-icons': [
    { setting: ['hicolor_privacy_icons'], id: 'mastodon-settings--hicolor_privacy_icons', message: { id: 'settings.hicolor_privacy_icons', defaultMessage: 'High color privacy icons' }, hint: { id: 'settings.hicolor_privacy_icons.hint', defaultMessage: 'Display privacy icons in bright and easily distinguishable colors' } },
  ],
  'compose-quick-buttons': [
    { setting: ['hide_compose_language'], id: 'mastodon-settings--show_compose_language', message: { id: 'settings.show_compose_language', defaultMessage: 'Show language selection in the compose box' }, inverted: true },
    { setting: ['show_clip_choice'], id: 'mastodon-settings--show_clip_choice', message: { id: 'settings.show_clip_choice', defaultMessage: 'Show clip selection in the compose box' } },
    { setting: ['show_schedule_button'], id: 'mastodon-settings--show_schedule_button', message: { id: 'settings.show_schedule_button', defaultMessage: 'Show schedule button in the compose box' } },
    { setting: ['show_draft_button'], id: 'mastodon-settings--show_draft_button', message: { id: 'settings.show_draft_button', defaultMessage: 'Show draft button in the compose box' }, hint: { id: 'settings.show_draft_button.hint', defaultMessage: 'Save drafts to the server and load them again from the compose box. Drafts stay available at the drafts column even when this is off' } },
    { setting: ['show_reaction_acceptance'], id: 'mastodon-settings--show_reaction_acceptance', message: { id: 'settings.show_reaction_acceptance', defaultMessage: 'Show reaction acceptance in the compose box' } },
  ],
  'compose-form': [
    { setting: ['inline_compose_timelines'], id: 'mastodon-settings--inline_compose_timelines', message: { id: 'settings.inline_compose_timelines', defaultMessage: 'Show the compose box at the top of timelines' }, hint: { id: 'settings.inline_compose_timelines.hint', defaultMessage: 'Twitter-style: display the compose box above the home, local and federated timelines (single-column mode only)' } },
    { setting: ['disable_inline_compose_reply_modal'], id: 'mastodon-settings--disable_inline_compose_reply_modal', message: { id: 'settings.disable_inline_compose_reply_modal', defaultMessage: 'Do not use a popup for replies' }, hint: { id: 'settings.disable_inline_compose_reply_modal.hint', defaultMessage: 'When inline compose is enabled, use the compose box at the top of the timeline for replies; detailed posts will return to the timeline' } },
    { setting: ['use_publish_toot'], id: 'mastodon-settings--use_publish_toot', message: { id: 'settings.use_publish_toot', defaultMessage: 'Use "뿌우" as the publish button label' } },
    { setting: ['show_content_type_choice'], id: 'mastodon-settings--show_content_type_choice', message: { id: 'settings.show_content_type_choice', defaultMessage: 'Show content-type choice when authoring toots' } },
    { setting: ['hide_mfm_compose_hint'], id: 'mastodon-settings--hide_mfm_compose_hint', message: { id: 'settings.hide_mfm_compose_hint', defaultMessage: 'Hide MFM preview and syntax link in the compose box' } },
  ],
  'compose-reply-behavior': [
    { setting: ['mention_reblogger'], id: 'mastodon-settings--mention_reblogger', message: { id: 'settings.mention_reblogger', defaultMessage: 'Mention booster when replying to a boosted post' } },
  ],
  'media-after-fullwidth': [
    { setting: ['media', 'no_autoplay_gifv'], id: 'mastodon-settings--media-no_autoplay_gifv', message: { id: 'settings.media_no_autoplay_gifv', defaultMessage: 'Do not autoplay attached GIFs' }, hint: { id: 'settings.media_no_autoplay_gifv_hint', defaultMessage: 'Attached GIF media will play on hover or click instead of automatically, even when GIF autoplay is enabled' } },
  ],
};

const LocalSettingsSlot = ({ intl, onChange, settings, slot }) => localSettingsSlots[slot]?.map(item => (
  <LocalSettingsPageItem
    key={item.id}
    settings={settings}
    item={item.setting}
    id={item.id}
    onChange={onChange}
    disabled={item.dependsOn ? !settings.getIn(item.dependsOn) : undefined}
    inverted={item.inverted}
    options={item.options?.map(option => ({ value: option.value, message: intl.formatMessage(option.message) }))}
  >
    <FormattedMessage {...item.message} />
    {item.hint && <span className='hint'><FormattedMessage {...item.hint} /></span>}
  </LocalSettingsPageItem>
));

LocalSettingsSlot.propTypes = {
  intl: PropTypes.object.isRequired,
  onChange: PropTypes.func.isRequired,
  settings: PropTypes.object.isRequired,
  slot: PropTypes.string.isRequired,
};

export const SharlayanLocalSettingsSlot = injectIntl(LocalSettingsSlot);

export const renderSharlayanLocalSettingsNavigationItems = (slot, { NavigationItem, index, intl, onNavigate }) => {
  const items = slot === 'after-general'
    ? [{ index: 1, icon: 'sliders', iconComponent: TuneIcon, title: intl.formatMessage(messages.quick_preferences) }]
    : [
      { index: 8, icon: 'unfold-less', iconComponent: UnfoldLessIcon, title: intl.formatMessage({ id: 'settings.collapsed_statuses', defaultMessage: 'Collapsed posts' }) },
      { index: 7, icon: 'drag', iconComponent: TuneIcon, title: intl.formatMessage(messages.status_action_bar) },
      { index: 6, icon: 'list', iconComponent: ListIcon, title: intl.formatMessage(messages.navigation_panel) },
      { index: 5, icon: 'cloud', iconComponent: CloudSyncIcon, title: intl.formatMessage(messages.sync) },
    ];

  return items.map(item => <NavigationItem key={item.index} active={index === item.index} onNavigate={onNavigate} {...item} />);
};

const LocalSettingsLayout = ({ children, intl, onClose }) => (
  <>
    <div className='glitch local-settings__header'>
      <span className='local-settings__header__title'>{intl.formatMessage(messages.title)}</span>
      <div className='local-settings__header__tools'>
        <a href={preferencesLink} className='local-settings__header__button' title={intl.formatMessage(messages.preferences)} aria-label={intl.formatMessage(messages.preferences)}><Icon id='cog' icon={SettingsIcon} /></a>
        <button type='button' onClick={onClose} className='local-settings__header__button' title={intl.formatMessage(messages.close)} aria-label={intl.formatMessage(messages.close)}><Icon id='times' icon={CloseIcon} /></button>
      </div>
    </div>
    <div className='glitch local-settings__content'>
      <div className='local-settings__page__decoration-before' />
      {children}
      <div className='local-settings__page__decoration-after' />
    </div>
  </>
);

LocalSettingsLayout.propTypes = {
  children: PropTypes.node.isRequired,
  intl: PropTypes.object.isRequired,
  onClose: PropTypes.func.isRequired,
};

export const SharlayanLocalSettingsLayout = injectIntl(LocalSettingsLayout);
