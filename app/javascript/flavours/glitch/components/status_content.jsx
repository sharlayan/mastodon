import PropTypes from 'prop-types';
import React from 'react';
import { PureComponent } from 'react';

import { FormattedMessage } from 'react-intl';

import classnames from 'classnames';
import { withRouter } from 'react-router-dom';

import ImmutablePropTypes from 'react-immutable-proptypes';
import { connect } from 'react-redux';

import ChevronRightIcon from '@/material-icons/400-24px/chevron_right.svg?react';
import { Icon } from 'flavours/glitch/components/icon';
import { Poll } from 'flavours/glitch/components/poll';
import { identityContextPropShape, withIdentity } from 'flavours/glitch/identity_context';
import { languages as preloadedLanguages } from 'flavours/glitch/initial_state';

import { EmojiHTML } from './emoji/html';
import { MfmRenderer, hasSensitiveFoldTags, MFM_FOLD_LENGTH_THRESHOLD } from './mfm';
import { injectIntl } from './intl';
import { HandledLink } from './status/handled_link';

import { EmojiInfoTooltip } from './emoji_info_tooltip';

const mfmDomParser = new DOMParser();

function extractPlainTextFromHtml(html) {
  const doc = mfmDomParser.parseFromString(html, 'text/html');
  for (const br of doc.querySelectorAll('br')) {
    br.replaceWith('\n');
  }
  for (const p of doc.querySelectorAll('p')) {
    p.after('\n');
  }
  return doc.body.textContent || '';
}

const MAX_HEIGHT = 706; // 22px * 32 (+ 2px padding at the top)

/**
 *
 * @param {any} status
 * @returns {string}
 */
export function getStatusContent(status) {
  return status.getIn(['translation', 'contentHtml']) || status.get('contentHtml');
}

class TranslateButton extends PureComponent {

  static propTypes = {
    translation: ImmutablePropTypes.map,
    onClick: PropTypes.func,
  };

  render () {
    const { translation, onClick } = this.props;

    if (translation) {
      const language     = preloadedLanguages.find(lang => lang[0] === translation.get('detected_source_language'));
      const languageName = language ? language[1] : translation.get('detected_source_language');
      const provider     = translation.get('provider');

      return (
        <div className='translate-button'>
          <button className='link-button' onClick={onClick}>
            <FormattedMessage id='status.show_original' defaultMessage='Show original' />
          </button>

          <div className='translate-button__meta'>
            <FormattedMessage id='status.translated_from_with' defaultMessage='Translated from {lang} using {provider}' values={{ lang: languageName, provider }} />
          </div>
        </div>
      );
    }

    return (
      <button className='status__content__translate-button' onClick={onClick}>
        <FormattedMessage id='status.translate' defaultMessage='Translate' />
      </button>
    );
  }

}

const mapStateToProps = state => ({
  languages: state.getIn(['server', 'translationLanguages', 'items']),
  localMfmEnabled: state.getIn(['meta', 'mfm_enabled']) !== false,
  localMfmAnimations: state.getIn(['meta', 'mfm_animations']) !== false,
  localMfmFoldMode: state.getIn(['meta', 'mfm_fold_mode']) ?? 'sensitive',
});

const compareUrls = (href1, href2) => {
  try {
    const url1 = new URL(href1);
    const url2 = new URL(href2);

    return url1.origin === url2.origin && url1.pathname === url2.pathname && url1.search === url2.search;
  } catch {
    return false;
  }
};

class StatusContent extends PureComponent {
  static propTypes = {
    identity: identityContextPropShape,
    status: ImmutablePropTypes.map.isRequired,
    statusContent: PropTypes.string,
    onTranslate: PropTypes.func,
    onClick: PropTypes.func,
    collapsible: PropTypes.bool,
    onCollapsedToggle: PropTypes.func,
    languages: ImmutablePropTypes.map,
    intl: PropTypes.object,
    mfmEnabled: PropTypes.bool,
    localMfmEnabled: PropTypes.bool,
    localMfmAnimations: PropTypes.bool,
    localMfmFoldMode: PropTypes.string,
    // from react-router
    match: PropTypes.object.isRequired,
    location: PropTypes.object.isRequired,
    history: PropTypes.object.isRequired
  };

  contentRef = React.createRef();

  _updateStatusLinks () {
    const node = this.contentRef.current;

    if (!node) {
      return;
    }

    const { status, onCollapsedToggle } = this.props;
    if (status.get('collapsed', null) === null && onCollapsedToggle) {
      const { collapsible, onClick } = this.props;
      const text = node.querySelector(':scope > .status__content__text');

      const collapsed =
          collapsible
          && onClick
          && (node.clientHeight > MAX_HEIGHT || (text !== null && text.scrollWidth > text.clientWidth))
          && status.get('spoiler_text').length === 0;

      onCollapsedToggle(collapsed);
    }
  }

  componentDidMount () {
    this._updateStatusLinks();
  }

  componentDidUpdate () {
    this._updateStatusLinks();
  }

  handleMouseDown = (e) => {
    this.startXY = [e.clientX, e.clientY];
  };

  handleMouseUp = (e) => {
    if (!this.startXY) {
      return;
    }

    const [ startX, startY ] = this.startXY;
    const [ deltaX, deltaY ] = [Math.abs(e.clientX - startX), Math.abs(e.clientY - startY)];

    let element = e.target;
    while (element !== e.currentTarget) {
      if (['button', 'video', 'a', 'label', 'canvas', 'summary', 'details'].includes(element.localName) || element.getAttribute('role') === 'button') {
        return;
      }
      element = element.parentNode;
    }

    if (deltaX + deltaY < 5 && (e.button === 0 || e.button === 1) && e.detail >= 1 && this.props.onClick) {
      this.props.onClick(e);
    }

    this.startXY = null;
  };

  handleTranslate = () => {
    this.props.onTranslate();
  };

  handleElement = (element, { key, ...props }, children) => {
    if (element instanceof HTMLAnchorElement) {
      const mention = this.props.status.get('mentions').find(item => compareUrls(element.href, item.get('url')));
      return (
        <HandledLink
          {...props}
          href={element.href}
          text={element.innerText}
          hashtagAccountId={this.props.status.getIn(['account', 'id'])}
          mention={mention?.toJSON()}
          key={key}
        >
          {children}
        </HandledLink>
      );
    } else if (element.classList.contains('quote-inline') && this.props.status.get('quote')) {
      return null;
    }
    return undefined;
  }

  render () {
    const { status, intl, statusContent } = this.props;

    const renderReadMore = this.props.onClick && status.get('collapsed');
    const contentLocale = intl.locale.replace(/[_-].*/, '');
    const targetLanguages = this.props.languages?.get(status.get('language') || 'und');
    const renderTranslate = this.props.onTranslate && this.props.identity.signedIn && ['public', 'unlisted'].includes(status.get('visibility')) && status.get('search_index').trim().length > 0 && targetLanguages?.includes(contentLocale);

    const content = (statusContent ?? getStatusContent(status)).replace(/(<br\s*\/?>)+[\s\n]*$/, '');
    const language = status.getIn(['translation', 'language']) || status.get('language');
    const isMfm = status.get('mfm') && this.props.mfmEnabled !== false && this.props.localMfmEnabled !== false;
    const mfmAnimationsEnabled = this.props.localMfmAnimations !== false;
    const mfmFoldMode = this.props.localMfmFoldMode ?? 'sensitive';
    const classNames = classnames('status__content', {
      'status__content--with-action': this.props.onClick && this.props.history,
      'status__content--collapsed': renderReadMore,
    });

    const readMoreButton = renderReadMore && (
      <button className='status__content__read-more-button' onClick={this.props.onClick} key='read-more'>
        <FormattedMessage id='status.read_more' defaultMessage='Read more' /><Icon id='angle-right' icon={ChevronRightIcon} />
      </button>
    );

    const translateButton = renderTranslate && (
      <TranslateButton onClick={this.handleTranslate} translation={status.get('translation')} />
    );

    const poll = !!status.get('poll') && (
      <Poll pollId={status.get('poll')} status={status} lang={language} />
    );

    // MFM content: use stored mfm_text if available, otherwise extract from HTML
    const mfmSourceText = status.get('mfm_text') || extractPlainTextFromHtml(content);
    const shouldFoldMfm = isMfm && (
      mfmFoldMode === 'all' ||
      (mfmFoldMode === 'sensitive' && hasSensitiveFoldTags(mfmSourceText)) ||
      mfmSourceText.length > MFM_FOLD_LENGTH_THRESHOLD
    );
    const contentElement = isMfm ? (
      <div className='status__content__text status__content__text--visible translate' lang={language}>
        {shouldFoldMfm ? (
          <details className='status__content__mfm-fold'>
            <summary>
              <FormattedMessage id='status.mfm_fold_expand' defaultMessage='Expand MFM post' />
            </summary>
            <MfmRenderer text={mfmSourceText} emojis={status.get('emojis')} animationsEnabled={mfmAnimationsEnabled} />
          </details>
        ) : (
          <MfmRenderer text={mfmSourceText} emojis={status.get('emojis')} animationsEnabled={mfmAnimationsEnabled} />
        )}
      </div>
    ) : (
      <EmojiHTML
        className='status__content__text status__content__text--visible translate'
        lang={language}
        htmlString={content}
        extraEmojis={status.get('emojis')}
        onElement={this.handleElement}
      />
    );

    if (this.props.onClick) {
      return (
        <>
          <div
            className={classNames}
            onMouseDown={this.handleMouseDown}
            onMouseUp={this.handleMouseUp}
            ref={this.contentRef}
            key='status-content'
          >
            {contentElement}

            {poll}
            {translateButton}
          </div>

          {readMoreButton}

          <EmojiInfoTooltip
            containerRef={this.contentRef}
            enabled
          />
        </>
      );
    } else {
      return (
        <div className={classNames} ref={this.contentRef}>
          {contentElement}

          {poll}
          {translateButton}

          <EmojiInfoTooltip
            containerRef={this.contentRef}
            enabled
          />
        </div>
      );
    }
  }

}

export default withRouter(withIdentity(connect(mapStateToProps)(injectIntl(StatusContent))));
