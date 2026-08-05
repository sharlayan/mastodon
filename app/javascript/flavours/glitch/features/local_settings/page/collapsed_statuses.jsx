import PropTypes from 'prop-types';

import { FormattedMessage } from 'react-intl';

import { parseCharacterLimit } from 'flavours/glitch/sharlayan/post_collapsing';

import LocalSettingsPageItem from './item';

const CollapsedStatusesSettings = ({ onChange, settings }) => (
  <div className='glitch local-settings__page collapsed'>
    <h1><FormattedMessage id='settings.collapsed_statuses' defaultMessage='Collapsed posts' /></h1>
    <LocalSettingsPageItem settings={settings} item={['collapsed', 'enabled']} id='mastodon-settings--collapsed-enabled' onChange={onChange}>
      <FormattedMessage id='settings.enable_collapsed' defaultMessage='Enable collapsed posts' />
      <span className='hint'><FormattedMessage id='settings.enable_collapsed_hint' defaultMessage='Collapsed posts hide parts of their content to take up less space. This is separate from the Content Warning feature.' /></span>
    </LocalSettingsPageItem>
    <LocalSettingsPageItem settings={settings} item={['collapsed', 'show_action_bar']} id='mastodon-settings--collapsed-show-action-bar' onChange={onChange} dependsOn={[['collapsed', 'enabled']]}>
      <FormattedMessage id='settings.show_action_bar' defaultMessage='Show action buttons in collapsed posts' />
    </LocalSettingsPageItem>
    <section>
      <h2><FormattedMessage id='settings.auto_collapse' defaultMessage='Automatic collapsing' /></h2>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'all']} id='mastodon-settings--collapsed-auto-all' onChange={onChange} dependsOn={[['collapsed', 'enabled']]}>
        <FormattedMessage id='settings.auto_collapse_all' defaultMessage='Everything' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'notifications']} id='mastodon-settings--collapsed-auto-notifications' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_notifications' defaultMessage='Notifications' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'lengthy']} id='mastodon-settings--collapsed-auto-lengthy' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_lengthy' defaultMessage='Lengthy posts' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'reblogs']} id='mastodon-settings--collapsed-auto-reblogs' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_reblogs' defaultMessage='Boosts' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'replies']} id='mastodon-settings--collapsed-auto-replies' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_replies' defaultMessage='Replies' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'quotes']} id='mastodon-settings--collapsed-auto-quotes' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_quotes' defaultMessage='Quotes' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'media']} id='mastodon-settings--collapsed-auto-media' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]}>
        <FormattedMessage id='settings.auto_collapse_media' defaultMessage='Posts with media' />
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'character_limit']} id='mastodon-settings--collapsed-auto-character-limit' placeholder='500' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]} inputProps={{ type: 'number', min: '1', max: '99999' }}>
        <FormattedMessage id='settings.auto_collapse_character_limit' defaultMessage='Character count for a post to be considered lengthy' />
        <span className='hint'><FormattedMessage id='settings.auto_collapse_character_limit_hint' defaultMessage='Leave blank to use the height setting instead.' /></span>
      </LocalSettingsPageItem>
      <LocalSettingsPageItem settings={settings} item={['collapsed', 'auto', 'height']} id='mastodon-settings--collapsed-auto-height' placeholder='400' onChange={onChange} dependsOn={[['collapsed', 'enabled']]} dependsOnNot={[['collapsed', 'auto', 'all']]} disabled={parseCharacterLimit(settings.getIn(['collapsed', 'auto', 'character_limit'])) !== null} inputProps={{ type: 'number', min: '200', max: '999' }}>
        <FormattedMessage id='settings.auto_collapse_height' defaultMessage='Height (in pixels) for a post to be considered lengthy' />
      </LocalSettingsPageItem>
    </section>
  </div>
);

CollapsedStatusesSettings.propTypes = {
  onChange: PropTypes.func.isRequired,
  settings: PropTypes.object.isRequired,
};

export default CollapsedStatusesSettings;
