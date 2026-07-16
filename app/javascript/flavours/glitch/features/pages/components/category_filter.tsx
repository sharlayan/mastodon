import { useCallback, useMemo } from 'react';

import { useIntl } from 'react-intl';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

export const CategoryFilter: React.FC<{
  pages: ApiPageJSON[];
  value: string;
  onChange: (category: string) => void;
}> = ({ pages, value, onChange }) => {
  const intl = useIntl();
  const categories = useMemo(
    () =>
      [
        ...new Set(
          pages.flatMap((page) => (page.category ? [page.category] : [])),
        ),
      ].sort((a, b) => a.localeCompare(b, intl.locale)),
    [intl.locale, pages],
  );
  const handleChange = useCallback(
    (event: React.ChangeEvent<HTMLSelectElement>) => {
      onChange(event.target.value);
    },
    [onChange],
  );
  const handleTabClick = useCallback(
    (event: React.MouseEvent<HTMLButtonElement>) => {
      onChange(event.currentTarget.dataset.category ?? '');
    },
    [onChange],
  );

  if (categories.length === 0) {
    return null;
  }

  const allLabel = intl.formatMessage({
    id: 'pages.category.all',
    defaultMessage: 'All',
  });
  const filterLabel = intl.formatMessage({
    id: 'pages.category_filter',
    defaultMessage: 'Category',
  });

  if (categories.length + 1 < 5) {
    return (
      <div
        className='page-category-filter page-category-filter--tabs'
        role='tablist'
        aria-label={filterLabel}
      >
        <button
          type='button'
          role='tab'
          className={value === '' ? 'active' : undefined}
          aria-selected={value === ''}
          data-category=''
          onClick={handleTabClick}
        >
          {allLabel}
        </button>
        {categories.map((category) => (
          <button
            type='button'
            role='tab'
            className={value === category ? 'active' : undefined}
            aria-selected={value === category}
            data-category={category}
            onClick={handleTabClick}
            key={category}
          >
            {category}
          </button>
        ))}
      </div>
    );
  }

  return (
    <label className='page-category-filter'>
      <span>{filterLabel}</span>
      <select value={value} onChange={handleChange}>
        <option value=''>{allLabel}</option>
        {categories.map((category) => (
          <option key={category} value={category}>
            {category}
          </option>
        ))}
      </select>
    </label>
  );
};
