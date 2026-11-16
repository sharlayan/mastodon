import { FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import classes from './styles.module.scss';

export const CircleVisibilityLabel: React.FC<{
  title?: string | null;
  className?: string;
}> = ({ title, className }) => {
  const intl = useIntl();

  if (!title) {
    return (
      <FormattedMessage id='privacy.circle.short' defaultMessage='Circle' />
    );
  }

  const label = intl.formatMessage(
    { id: 'privacy.circle.named', defaultMessage: 'Circle: {name}' },
    { name: title },
  );

  return (
    <span className={classNames(classes.label, className)} title={label}>
      {label}
    </span>
  );
};
