import { useCallback, useMemo } from 'react';

import { useIntl } from 'react-intl';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

export const PageShowCategoryMenu: React.FC<{
  pages: ApiPageJSON[];
  value: string;
  onChange: (category: string) => void;
  position?: 'top' | 'bottom';
}> = ({ pages, value, onChange, position = 'top' }) => {
  const intl = useIntl();
  const categories = useMemo(
    () =>
      [
        ...new Set(
          pages.flatMap((accountPage) =>
            accountPage.category ? [accountPage.category] : [],
          ),
        ),
      ].sort((left, right) => left.localeCompare(right, intl.locale)),
    [intl.locale, pages],
  );
  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      onChange(event.currentTarget.dataset.category ?? '');
    },
    [onChange],
  );

  if (categories.length === 0) {
    return null;
  }

  return (
    <nav
      className={`page-show__category-menu page-show__category-menu--${position}`}
      aria-label={intl.formatMessage({
        id: 'pages.category_filter',
        defaultMessage: 'Category',
      })}
    >
      <button
        type='button'
        className={value === '' ? 'active' : undefined}
        data-category=''
        aria-pressed={value === ''}
        onClick={handleClick}
      >
        {intl.formatMessage({
          id: 'pages.category.all',
          defaultMessage: 'All',
        })}
      </button>
      {categories.map((category) => (
        <button
          key={category}
          type='button'
          className={value === category ? 'active' : undefined}
          data-category={category}
          aria-pressed={value === category}
          onClick={handleClick}
        >
          {category}
        </button>
      ))}
    </nav>
  );
};
