import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { Callout } from '@/flavours/glitch/components/callout';
import CloseIcon from '@/material-icons/400-24px/close.svg?react';
import { submitReport } from 'flavours/glitch/actions/reports';
import { fetchServer } from 'flavours/glitch/actions/server';
import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';
import { Button } from 'flavours/glitch/components/button';
import { IconButton } from 'flavours/glitch/components/icon_button';
import { NavigationFocusTarget } from 'flavours/glitch/components/navigation_focus_target';
import { useAppDispatch } from 'flavours/glitch/store';

import Category from '../../report/category';
import Comment from '../../report/comment';
import Rules from '../../report/rules';

const messages = defineMessages({
  close: { id: 'lightbox.close', defaultMessage: 'Close' },
});

const PageThanks: React.FC<{ onClose: () => void }> = ({ onClose }) => (
  <>
    <NavigationFocusTarget as='h1' className='report-dialog-modal__title'>
      <FormattedMessage
        id='report.thanks.title_actionable'
        defaultMessage="Thanks for reporting, we'll look into this."
      />
    </NavigationFocusTarget>

    <div className='flex-spacer' />

    <div className='report-dialog-modal__actions'>
      <Button onClick={onClose}>
        <FormattedMessage id='report.close' defaultMessage='Done' />
      </Button>
    </div>
  </>
);

export const ReportPageModal: React.FC<{
  page: ApiPageJSON;
  onClose: () => void;
}> = ({ page, onClose }) => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const { id: pageId, title, name, account_id } = page;

  useEffect(() => {
    void dispatch(fetchServer());
  }, [dispatch]);

  const [submitState, setSubmitState] = useState<
    'idle' | 'submitting' | 'submitted' | 'error'
  >('idle');
  const [step, setStep] = useState<'category' | 'rules' | 'comment' | 'thanks'>(
    'category',
  );
  const [category, setCategory] = useState<
    'spam' | 'legal' | 'violation' | 'other' | null
  >(null);
  const [selectedRuleIds, setSelectedRuleIds] = useState<string[]>([]);
  const [comment, setComment] = useState('');

  const handleDomainToggle = useCallback(() => undefined, []);

  const handleRuleToggle = useCallback((ruleId: string) => {
    setSelectedRuleIds((ruleIds) =>
      ruleIds.includes(ruleId)
        ? ruleIds.filter((id) => ruleId !== id)
        : [...ruleIds, ruleId],
    );
  }, []);

  const handleNextStep = useCallback(() => {
    if (step === 'category' && category === 'violation') {
      setStep('rules');
    } else {
      setStep('comment');
    }
  }, [category, step]);

  const handleSubmit = useCallback(() => {
    setSubmitState('submitting');

    dispatch(
      submitReport(
        {
          account_id,
          status_ids: [],
          collection_ids: [],
          page_ids: [pageId],
          comment,
          forward: false,
          category: category ?? 'other',
          rule_ids: selectedRuleIds,
        },
        () => {
          setSubmitState('submitted');
          setStep('thanks');
        },
        () => {
          setSubmitState('error');
        },
      ),
    );
  }, [account_id, category, selectedRuleIds, comment, dispatch, pageId]);

  let stepComponent;

  switch (step) {
    case 'category':
      stepComponent = (
        <Category
          onNextStep={handleNextStep}
          startedFrom='page'
          category={category}
          onChangeCategory={setCategory}
        />
      );
      break;
    case 'rules':
      stepComponent = (
        <Rules
          onNextStep={handleNextStep}
          selectedRuleIds={selectedRuleIds}
          onToggle={handleRuleToggle}
        />
      );
      break;
    case 'comment':
      stepComponent = (
        <Comment
          submitError={
            submitState === 'error' && (
              <Callout
                variant='error'
                title={
                  <FormattedMessage
                    id='report.submission_error'
                    defaultMessage='Report could not be submitted'
                  />
                }
              >
                <FormattedMessage
                  id='report.submission_error_details'
                  defaultMessage='Please check your network connection and try again later.'
                />
              </Callout>
            )
          }
          onSubmit={handleSubmit}
          isSubmitting={submitState === 'submitting'}
          comment={comment}
          statusIds={[]}
          selectedDomains={[]}
          onChangeComment={setComment}
          onToggleDomain={handleDomainToggle}
        />
      );
      break;
    case 'thanks':
      stepComponent = <PageThanks onClose={onClose} />;
  }

  return (
    <div className='modal-root__modal report-dialog-modal'>
      <div className='report-modal__target'>
        <IconButton
          className='report-modal__close'
          title={intl.formatMessage(messages.close)}
          icon='times'
          iconComponent={CloseIcon}
          onClick={onClose}
        />
        <FormattedMessage
          id='report.target'
          defaultMessage='Report {target}'
          values={{ target: <strong>{title || name}</strong> }}
        />
      </div>

      <div className='report-dialog-modal__container'>{stepComponent}</div>
    </div>
  );
};
