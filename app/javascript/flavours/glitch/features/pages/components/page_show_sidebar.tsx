import { useIntl } from 'react-intl';

import { Link } from 'react-router-dom';

import type { ApiPageJSON } from 'flavours/glitch/api_types/pages';

import { PageListItem } from './page_list_item';

export const PageShowSidebar: React.FC<{
  page: ApiPageJSON;
  pages: ApiPageJSON[];
  isBlogView: boolean;
  position?: 'side' | 'bottom';
}> = ({ page, pages, isBlogView, position = 'side' }) => {
  const intl = useIntl();

  return (
    <aside
      className={`page-show__sidebar page-show__sidebar--${position}`}
      aria-label={intl.formatMessage({
        id: 'account.pages',
        defaultMessage: 'Pages',
      })}
    >
      {isBlogView ? (
        <>
          <ol className='page-show__blog-list'>
            {pages.map((accountPage) => (
              <li key={accountPage.id}>
                <Link
                  to={`/@${accountPage.account.acct}/pages/${encodeURIComponent(accountPage.name)}`}
                  aria-current={accountPage.id === page.id ? 'page' : undefined}
                >
                  {accountPage.title.length > 0
                    ? accountPage.title
                    : accountPage.name}
                </Link>
              </li>
            ))}
          </ol>
          <PageShowSidebarList page={page} pages={pages} />
        </>
      ) : (
        <PageShowSidebarList page={page} pages={pages} />
      )}
    </aside>
  );
};

const PageShowSidebarList: React.FC<{
  page: ApiPageJSON;
  pages: ApiPageJSON[];
}> = ({ page, pages }) => (
  <div className='page-show__sidebar-list'>
    {pages.map((accountPage) => (
      <PageListItem
        key={accountPage.id}
        page={accountPage}
        active={accountPage.id === page.id}
        replaceHistory
      />
    ))}
  </div>
);
