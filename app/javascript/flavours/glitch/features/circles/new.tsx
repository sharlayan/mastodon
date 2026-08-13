import { useCallback, useState, useEffect } from 'react';

import { defineMessages, useIntl, FormattedMessage } from 'react-intl';

import { useParams, useHistory, Link } from 'react-router-dom';

import { isFulfilled } from '@reduxjs/toolkit';

import { Helmet } from '@unhead/react/helmet';

import { NotSignedInIndicator } from '@/flavours/glitch/components/not_signed_in_indicator';
import { useIdentity } from '@/flavours/glitch/identity_context';
import ChevronRightIcon from '@/material-icons/400-24px/chevron_right.svg?react';
import GroupIcon from '@/material-icons/400-24px/group.svg?react';
import { fetchCircle } from 'flavours/glitch/actions/circles';
import {
  createCircle,
  updateCircle,
} from 'flavours/glitch/actions/circles_typed';
import { apiGetCircleAccounts } from 'flavours/glitch/api/circles';
import type { ApiAccountJSON } from 'flavours/glitch/api_types/accounts';
import { Avatar } from 'flavours/glitch/components/avatar';
import { AvatarGroup } from 'flavours/glitch/components/avatar_group';
import { Column } from 'flavours/glitch/components/column';
import { ColumnHeader } from 'flavours/glitch/components/column/header';
import { TextInputField } from 'flavours/glitch/components/form_fields';
import { Icon } from 'flavours/glitch/components/icon';
import { LoadingIndicator } from 'flavours/glitch/components/loading_indicator';
import type { Circle } from 'flavours/glitch/models/circle';
import { useAppDispatch, useAppSelector } from 'flavours/glitch/store';

import { messages as membersMessages } from './members';

const messages = defineMessages({
  edit: { id: 'column.edit_circle', defaultMessage: 'Edit circle' },
  create: { id: 'column.create_circle', defaultMessage: 'Create circle' },
});

const MembersLink: React.FC<{
  id: string;
}> = ({ id }) => {
  const intl = useIntl();
  const [avatarCount, setAvatarCount] = useState(0);
  const [avatarAccounts, setAvatarAccounts] = useState<ApiAccountJSON[]>([]);

  useEffect(() => {
    void apiGetCircleAccounts(id)
      .then((data) => {
        setAvatarCount(data.length);
        setAvatarAccounts(data.slice(0, 3));
        return '';
      })
      .catch(() => undefined);
  }, [id]);

  return (
    <Link to={`/circles/${id}/members`} className='app-form__link'>
      <div className='app-form__link__text'>
        <strong>
          {intl.formatMessage(membersMessages.manageMembers)}
          <Icon id='chevron_right' icon={ChevronRightIcon} />
        </strong>
        <FormattedMessage
          id='circles.circle_members_count'
          defaultMessage='{count, plural, one {# member} other {# members}}'
          values={{ count: avatarCount }}
        />
      </div>

      <AvatarGroup compact>
        {avatarAccounts.map((a) => (
          <Avatar key={a.id} account={a} size={30} />
        ))}
      </AvatarGroup>
    </Link>
  );
};

const NewCircle: React.FC<{ circle?: Circle | null }> = ({ circle }) => {
  const dispatch = useAppDispatch();
  const history = useHistory();

  const { id, title: initialTitle = '' } = circle ?? {};

  const [title, setTitle] = useState(initialTitle);
  const [submitting, setSubmitting] = useState(false);

  const handleTitleChange = useCallback(
    ({ target: { value } }: React.ChangeEvent<HTMLInputElement>) => {
      setTitle(value);
    },
    [setTitle],
  );

  const handleSubmit = useCallback(() => {
    setSubmitting(true);

    if (id) {
      void dispatch(updateCircle({ id, title })).then(() => {
        setSubmitting(false);
        return '';
      });
    } else {
      void dispatch(createCircle({ title })).then((result) => {
        setSubmitting(false);

        if (isFulfilled(result)) {
          history.replace(`/circles/${result.payload.id}/edit`);
          history.push(`/circles/${result.payload.id}/members`);
        }

        return '';
      });
    }
  }, [history, dispatch, setSubmitting, id, title]);

  return (
    <form className='simple_form app-form' onSubmit={handleSubmit}>
      <div className='fields-group'>
        <TextInputField
          required
          maxLength={30}
          label={
            <FormattedMessage
              id='circles.circle_name'
              defaultMessage='Circle name'
            />
          }
          value={title}
          onChange={handleTitleChange}
          id='circle_title'
        />
      </div>

      {id && (
        <div className='fields-group'>
          <MembersLink id={id} />
        </div>
      )}

      <div className='actions'>
        <button className='button' type='submit'>
          {submitting ? (
            <LoadingIndicator />
          ) : id ? (
            <FormattedMessage id='circles.save' defaultMessage='Save' />
          ) : (
            <FormattedMessage id='circles.create' defaultMessage='Create' />
          )}
        </button>
      </div>
    </form>
  );
};

const NewCircleWrapper: React.FC<{
  multiColumn?: boolean;
}> = ({ multiColumn }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { signedIn } = useIdentity();
  const { id } = useParams<{ id?: string }>();
  const circle = useAppSelector((state) =>
    id ? state.circles.get(id) : undefined,
  );

  useEffect(() => {
    if (signedIn && id) {
      dispatch(fetchCircle(id));
    }
  }, [dispatch, signedIn, id]);

  const isLoading = id && !circle;

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(id ? messages.edit : messages.create)}
    >
      <ColumnHeader
        title={intl.formatMessage(id ? messages.edit : messages.create)}
        icon='group'
        iconComponent={GroupIcon}
        multiColumn={multiColumn}
        showBackButton
      />

      <div className='scrollable'>
        {!signedIn ? (
          <NotSignedInIndicator />
        ) : isLoading ? (
          <LoadingIndicator />
        ) : (
          <NewCircle circle={circle} />
        )}
      </div>

      <Helmet>
        <title>
          {intl.formatMessage(id ? messages.edit : messages.create)}
        </title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default NewCircleWrapper;
