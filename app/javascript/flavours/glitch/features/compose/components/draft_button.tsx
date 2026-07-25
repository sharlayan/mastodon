import { useCallback, useState } from 'react';
import type { FC } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import type { List as ImmutableList, Map as ImmutableMap } from 'immutable';

import {
  fetchStatusDrafts,
  setComposeToStatusDraft,
} from '@/flavours/glitch/actions/status_drafts';
import { Icon } from '@/flavours/glitch/components/icon';
import { Popover } from '@/flavours/glitch/components/popover';
import { RelativeTimestamp } from '@/flavours/glitch/components/relative_timestamp';
import { useAppDispatch, useAppSelector } from '@/flavours/glitch/store';
import SaveIcon from '@/material-icons/400-24px/save.svg?react';

const messages = defineMessages({
  draft: { id: 'compose_form.draft.label', defaultMessage: 'Draft' },
  save: { id: 'compose_form.draft.save', defaultMessage: 'Save' },
  load: { id: 'compose_form.draft.load', defaultMessage: 'Load' },
  empty: {
    id: 'compose_form.draft.empty',
    defaultMessage: 'No saved drafts',
  },
  untitled: {
    id: 'compose_form.draft.untitled',
    defaultMessage: 'Empty draft',
  },
});

type StatusDraft = ImmutableMap<string, unknown>;

const DRAFT_PREVIEW_LENGTH = 60;

const draftPreview = (draft: StatusDraft) => {
  const params = draft.get('params') as ImmutableMap<string, unknown>;
  const spoiler = (params.get('spoiler_text') as string | undefined) ?? '';
  const text = (params.get('status') as string | undefined) ?? '';
  const preview = (spoiler || text).replace(/\s+/g, ' ').trim();

  if (preview.length <= DRAFT_PREVIEW_LENGTH) {
    return preview;
  }

  return `${preview.slice(0, DRAFT_PREVIEW_LENGTH)}…`;
};

interface DraftButtonProps {
  disabled?: boolean;
  onSaveDraft: () => void;
}

export const DraftButton: FC<DraftButtonProps> = ({
  disabled = false,
  onSaveDraft,
}) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [popoverTarget, setPopoverTarget] = useState<HTMLDivElement | null>(
    null,
  );
  const [isOpen, setIsOpen] = useState(false);
  const [showList, setShowList] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const visible = useAppSelector(
    (state) =>
      (state.local_settings as ImmutableMap<string, unknown>).get(
        'show_draft_button',
        false,
      ) as boolean,
  );
  const drafts = useAppSelector(
    (state) =>
      (state.status_drafts as ImmutableMap<string, unknown>).get(
        'items',
      ) as ImmutableList<StatusDraft>,
  );

  const handleClose = useCallback(() => {
    setIsOpen(false);
    setShowList(false);
  }, []);

  const handleToggle = useCallback(() => {
    setShowList(false);
    setIsOpen((prev) => !prev);
  }, []);

  const handleSave = useCallback(() => {
    onSaveDraft();
    handleClose();
  }, [onSaveDraft, handleClose]);

  const loadDraft = useCallback(
    (draft?: StatusDraft) => {
      if (!draft) {
        return;
      }

      dispatch(setComposeToStatusDraft(draft));
      handleClose();
    },
    [dispatch, handleClose],
  );

  const handleDraftClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      loadDraft(drafts.get(Number(event.currentTarget.dataset.index)));
    },
    [drafts, loadDraft],
  );

  // A single saved draft has nothing to pick from, so load it right away
  // instead of showing a one-item list.
  const handleLoad = useCallback(() => {
    setIsLoading(true);

    (
      dispatch(
        fetchStatusDrafts(),
      ) as Promise<ImmutableList<StatusDraft> | null>
    )
      .then((items) => {
        setIsLoading(false);

        if (!items) {
          handleClose();
        } else if (items.size === 1) {
          loadDraft(items.first());
        } else {
          setShowList(true);
        }

        return items;
      })
      .catch(() => {
        setIsLoading(false);
        handleClose();
      });
  }, [dispatch, loadDraft, handleClose]);

  if (!visible) {
    return null;
  }

  return (
    <div ref={setPopoverTarget}>
      <button
        type='button'
        title={intl.formatMessage(messages.draft)}
        aria-expanded={isOpen}
        onClick={handleToggle}
        disabled={disabled}
        className={classNames('dropdown-button', { active: isOpen })}
      >
        <Icon id='save' icon={SaveIcon} />
        <span className='dropdown-button__label'>
          {intl.formatMessage(messages.draft)}
        </span>
      </button>

      <Popover
        isOpen={isOpen}
        offset={5}
        reference={popoverTarget}
        onClose={handleClose}
      >
        {({ props, placement }) => (
          <div {...props}>
            <div
              className={`dropdown-animation dropdown-menu draft-dropdown__dropdown ${placement}`}
            >
              <div className='dropdown-menu__container'>
                <ul
                  className={classNames('dropdown-menu__container__list', {
                    'dropdown-menu__container__list--scrollable': showList,
                  })}
                >
                  {!showList && (
                    <>
                      <li className='dropdown-menu__item'>
                        <button type='button' onClick={handleSave}>
                          {intl.formatMessage(messages.save)}
                        </button>
                      </li>
                      <li className='dropdown-menu__item'>
                        <button
                          type='button'
                          onClick={handleLoad}
                          aria-disabled={isLoading}
                        >
                          {intl.formatMessage(messages.load)}
                        </button>
                      </li>
                    </>
                  )}

                  {showList && drafts.size === 0 && (
                    <li className='dropdown-menu__item draft-dropdown__empty'>
                      {intl.formatMessage(messages.empty)}
                    </li>
                  )}

                  {showList &&
                    drafts.map((draft, index) => {
                      const preview = draftPreview(draft);

                      return (
                        <li
                          className='dropdown-menu__item'
                          key={draft.get('id') as string}
                        >
                          <button
                            type='button'
                            data-index={index}
                            onClick={handleDraftClick}
                          >
                            <span className='dropdown-menu__item-content'>
                              <span className='draft-dropdown__item__text'>
                                {preview ||
                                  intl.formatMessage(messages.untitled)}
                              </span>
                              <span className='dropdown-menu__item-subtitle'>
                                <RelativeTimestamp
                                  timestamp={draft.get('updated_at') as string}
                                />
                              </span>
                            </span>
                          </button>
                        </li>
                      );
                    })}
                </ul>
              </div>
            </div>
          </div>
        )}
      </Popover>
    </div>
  );
};
