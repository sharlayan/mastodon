import type { ChangeEvent, ReactNode } from 'react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import type { ApiPageWritingStatisticsJSON } from 'flavours/glitch/api_types/pages';

const messages = defineMessages({
  amount: { id: 'pages.statistics.amount', defaultMessage: 'Writing amount' },
  activity: {
    id: 'pages.statistics.activity',
    defaultMessage: 'Page activity',
  },
  total: {
    id: 'pages.statistics.total',
    defaultMessage: '{count} total characters',
  },
  characters: {
    id: 'pages.statistics.characters',
    defaultMessage: '{count, number} characters',
  },
  thisWeek: {
    id: 'pages.statistics.period.this_week',
    defaultMessage: 'This week',
  },
  oneWeekAgo: {
    id: 'pages.statistics.period.one_week_ago',
    defaultMessage: '1 week ago',
  },
  twoWeeksAgo: {
    id: 'pages.statistics.period.two_weeks_ago',
    defaultMessage: '2 weeks ago',
  },
  threeWeeksAgo: {
    id: 'pages.statistics.period.three_weeks_ago',
    defaultMessage: '3 weeks ago',
  },
  thisMonth: {
    id: 'pages.statistics.period.this_month',
    defaultMessage: 'This month',
  },
  lastMonth: {
    id: 'pages.statistics.period.last_month',
    defaultMessage: 'Last month',
  },
  all: { id: 'pages.statistics.period.all', defaultMessage: 'All' },
  periodReport: {
    id: 'pages.statistics.report.period',
    defaultMessage: 'Period summary',
  },
  monthlyReport: {
    id: 'pages.statistics.report.monthly',
    defaultMessage: 'Monthly report',
  },
  selectMonth: {
    id: 'pages.statistics.report.select_month',
    defaultMessage: 'Select month',
  },
  monthTotal: {
    id: 'pages.statistics.report.month_total',
    defaultMessage: 'Month total',
  },
  weekOfMonth: {
    id: 'pages.statistics.report.week_of_month',
    defaultMessage: 'Week {number}',
  },
  created: { id: 'pages.statistics.created', defaultMessage: 'New page' },
  updated: { id: 'pages.statistics.updated', defaultMessage: 'Updated page' },
  none: { id: 'pages.statistics.none', defaultMessage: 'No activity' },
  delta: {
    id: 'pages.statistics.delta',
    defaultMessage: '{count, number, ::sign-always} characters',
  },
});

const MINIMUM_VISIBLE_DAYS = 30;
const MAXIMUM_VISIBLE_DAYS = 365;
const CELL_SIZE = 10;
const CELL_GAP = 3;
const RESERVED_WEEK_COLUMNS = 4;
const DAY_IN_MILLISECONDS = 86_400_000;

const parseDateKey = (date: string) => new Date(`${date}T00:00:00Z`);
const toDateKey = (date: Date) => date.toISOString().slice(0, 10);
const shiftDate = (date: Date, days: number) =>
  new Date(date.getTime() + days * DAY_IN_MILLISECONDS);

const startOfWeek = (date: Date) => {
  const weekday = (date.getUTCDay() + 6) % 7;
  return shiftDate(date, -weekday);
};

interface MonthlyWeek {
  number: number;
  value: number;
}

export const buildMonthlyWeeks = (
  days: ApiPageWritingStatisticsJSON['days'],
  month: string,
  lastDate: string,
): MonthlyWeek[] => {
  if (!month) return [];

  const [year = 1970, monthNumber = 1] = month.split('-').map(Number);
  const firstWeekday =
    (new Date(Date.UTC(year, monthNumber - 1, 1)).getUTCDay() + 6) % 7;
  const daysInMonth = new Date(Date.UTC(year, monthNumber, 0)).getUTCDate();
  const lastDay =
    lastDate.startsWith(`${month}-`) && lastDate.slice(0, 7) === month
      ? Number(lastDate.slice(-2))
      : daysInMonth;
  const lastWeekNumber = Math.floor((lastDay - 1 + firstWeekday) / 7) + 1;
  const weeks = new Map<number, number>(
    Array.from({ length: lastWeekNumber }, (_, index) => [index + 1, 0]),
  );

  for (const day of days) {
    if (!day.date.startsWith(`${month}-`)) continue;
    const dayOfMonth = Number(day.date.slice(-2));
    if (dayOfMonth > lastDay) continue;
    const weekNumber = Math.floor((dayOfMonth - 1 + firstWeekday) / 7) + 1;
    weeks.set(weekNumber, (weeks.get(weekNumber) ?? 0) + day.characters_delta);
  }

  return [...weeks].map(([number, value]) => ({ number, value }));
};

const weekdayFromMonday = (date: string) => {
  const [year = 1970, month = 1, day = 5] = date.split('-').map(Number);
  const weekday = new Date(year, month - 1, day).getDay();
  return (weekday + 6) % 7;
};

const nearestDayCount = (
  boundary: number,
  lastWeekday: number,
  direction: 'up' | 'down',
) => {
  const remainder = (boundary - (lastWeekday + 1)) % 7;
  if (remainder === 0) return boundary;

  return direction === 'up'
    ? boundary + ((7 - remainder) % 7)
    : boundary - ((remainder + 7) % 7);
};

export const WritingStatistics: React.FC<{
  statistics: ApiPageWritingStatisticsJSON;
  showReport: boolean;
  reportToggle: ReactNode;
}> = ({ statistics, showReport, reportToggle }) => {
  const intl = useIntl();
  const containerRef = useRef<HTMLDivElement>(null);
  const [visibleDays, setVisibleDays] = useState(MINIMUM_VISIBLE_DAYS);
  const [activeTab, setActiveTab] = useState<'amount' | 'activity'>('amount');
  const [reportTab, setReportTab] = useState<'period' | 'monthly'>('period');
  const [selectedMonth, setSelectedMonth] = useState(
    statistics.first_written_on
      ? (statistics.days.at(-1)?.date.slice(0, 7) ?? '')
      : '',
  );
  const lastWeekday = useMemo(
    () => weekdayFromMonday(statistics.days.at(-1)?.date ?? ''),
    [statistics.days],
  );

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return undefined;

    const update = () => {
      const fittingColumns = Math.floor(
        (container.clientWidth + CELL_GAP) / (CELL_SIZE + CELL_GAP),
      );
      const columns = Math.max(1, fittingColumns - RESERVED_WEEK_COLUMNS);
      const minimumDays = nearestDayCount(
        MINIMUM_VISIBLE_DAYS,
        lastWeekday,
        'up',
      );
      const maximumDays = nearestDayCount(
        MAXIMUM_VISIBLE_DAYS,
        lastWeekday,
        'down',
      );
      const fittingDays = (columns - 1) * 7 + lastWeekday + 1;
      setVisibleDays(Math.min(maximumDays, Math.max(minimumDays, fittingDays)));
    };
    const observer = new ResizeObserver(update);
    observer.observe(container);
    update();
    return () => {
      observer.disconnect();
    };
  }, [lastWeekday]);

  const days = statistics.days.slice(-visibleDays);
  const maximum = useMemo(
    () => Math.max(1, ...days.map((day) => Math.max(0, day.characters_delta))),
    [days],
  );
  const amountSummaries = useMemo(() => {
    const lastDate = statistics.days.at(-1)?.date;
    if (!lastDate) return [];

    const anchor = parseDateKey(lastDate);
    const currentWeekStart = startOfWeek(anchor);
    const currentMonthStart = new Date(
      Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth(), 1),
    );
    const lastMonthStart = new Date(
      Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() - 1, 1),
    );
    const sum = (start: Date, end: Date) => {
      const startKey = toDateKey(start);
      const endKey = toDateKey(end);
      return statistics.days.reduce(
        (total, day) =>
          day.date >= startKey && day.date <= endKey
            ? total + day.characters_delta
            : total,
        0,
      );
    };
    const week = (offset: number) => {
      const start = shiftDate(currentWeekStart, offset * -7);
      const end = offset === 0 ? anchor : shiftDate(start, 6);
      return sum(start, end);
    };

    return [
      { label: messages.thisWeek, value: week(0) },
      { label: messages.oneWeekAgo, value: week(1) },
      { label: messages.twoWeeksAgo, value: week(2) },
      { label: messages.threeWeeksAgo, value: week(3) },
      { label: messages.thisMonth, value: sum(currentMonthStart, anchor) },
      {
        label: messages.lastMonth,
        value: sum(lastMonthStart, shiftDate(currentMonthStart, -1)),
      },
      {
        label: messages.all,
        value: statistics.total_characters,
        isTotal: true,
      },
    ];
  }, [statistics]);
  const availableMonths = useMemo(
    () =>
      statistics.first_written_on
        ? [
            ...new Set(
              statistics.days.map((day) => day.date.slice(0, 7)).reverse(),
            ),
          ].filter(
            (month) =>
              month >= (statistics.first_written_on?.slice(0, 7) ?? ''),
          )
        : [],
    [statistics.days, statistics.first_written_on],
  );
  const monthlyWeeks = useMemo(
    () =>
      buildMonthlyWeeks(
        statistics.days,
        selectedMonth,
        statistics.days.at(-1)?.date ?? '',
      ),
    [selectedMonth, statistics.days],
  );
  const monthlyTotal = useMemo(
    () => monthlyWeeks.reduce((total, week) => total + week.value, 0),
    [monthlyWeeks],
  );
  const amountTitle = useCallback(
    (day: ApiPageWritingStatisticsJSON['days'][number]) =>
      `${intl.formatDate(day.date)} · ${intl.formatMessage(messages.delta, { count: day.characters_delta })}`,
    [intl],
  );
  const amountCellClass = useCallback(
    (day: ApiPageWritingStatisticsJSON['days'][number]) => {
      if (day.characters_delta < 0) return 'is-negative';
      if (day.characters_delta === 0) return 'level-0';
      return `level-${Math.max(1, Math.ceil((day.characters_delta / maximum) * 4))}`;
    },
    [maximum],
  );
  const activityTitle = useCallback(
    (day: ApiPageWritingStatisticsJSON['days'][number]) =>
      `${intl.formatDate(day.date)} · ${intl.formatMessage(messages[day.activity])}`,
    [intl],
  );
  const activityCellClass = useCallback(
    (day: ApiPageWritingStatisticsJSON['days'][number]) => `is-${day.activity}`,
    [],
  );
  const showAmount = useCallback(() => {
    setActiveTab('amount');
  }, []);
  const showActivity = useCallback(() => {
    setActiveTab('activity');
  }, []);
  const showPeriodReport = useCallback(() => {
    setReportTab('period');
  }, []);
  const showMonthlyReport = useCallback(() => {
    setReportTab('monthly');
  }, []);
  const changeSelectedMonth = useCallback(
    (event: ChangeEvent<HTMLSelectElement>) => {
      setSelectedMonth(event.currentTarget.value);
    },
    [],
  );

  return (
    <div className='page-writing-statistics'>
      <div className='page-writing-statistics__controls'>
        <div
          className='page-writing-statistics__tabs'
          role='tablist'
          aria-label={intl.formatMessage(messages.activity)}
        >
          <button
            type='button'
            role='tab'
            aria-selected={activeTab === 'amount'}
            className={activeTab === 'amount' ? 'active' : undefined}
            onClick={showAmount}
          >
            {intl.formatMessage(messages.amount)}
          </button>
          <button
            type='button'
            role='tab'
            aria-selected={activeTab === 'activity'}
            className={activeTab === 'activity' ? 'active' : undefined}
            onClick={showActivity}
          >
            {intl.formatMessage(messages.activity)}
          </button>
        </div>
        {reportToggle}
      </div>
      <div className='page-writing-statistics__viewport' ref={containerRef}>
        {activeTab === 'amount' ? (
          <Heatmap
            label={intl.formatMessage(messages.amount)}
            days={days}
            className='page-writing-statistics__amount'
            title={amountTitle}
            cellClass={amountCellClass}
          />
        ) : (
          <Heatmap
            label={intl.formatMessage(messages.activity)}
            days={days}
            className='page-writing-statistics__activity'
            title={activityTitle}
            cellClass={activityCellClass}
          />
        )}
      </div>
      {activeTab === 'amount' && showReport && (
        <section className='page-writing-statistics__report'>
          <div className='page-writing-statistics__report-header'>
            <div
              className='page-writing-statistics__report-tabs'
              role='tablist'
              aria-label={intl.formatMessage(messages.amount)}
            >
              <button
                type='button'
                role='tab'
                aria-selected={reportTab === 'period'}
                className={reportTab === 'period' ? 'active' : undefined}
                onClick={showPeriodReport}
              >
                {intl.formatMessage(messages.periodReport)}
              </button>
              <button
                type='button'
                role='tab'
                aria-selected={reportTab === 'monthly'}
                className={reportTab === 'monthly' ? 'active' : undefined}
                onClick={showMonthlyReport}
              >
                {intl.formatMessage(messages.monthlyReport)}
              </button>
            </div>
            {reportTab === 'monthly' && (
              <select
                className='page-writing-statistics__month-select'
                aria-label={intl.formatMessage(messages.selectMonth)}
                value={selectedMonth}
                onChange={changeSelectedMonth}
              >
                {availableMonths.map((month) => (
                  <option key={month} value={month}>
                    {intl.formatDate(parseDateKey(`${month}-01`), {
                      year: 'numeric',
                      month: 'long',
                      timeZone: 'UTC',
                    })}
                  </option>
                ))}
              </select>
            )}
          </div>
          {reportTab === 'period' ? (
            <dl className='page-writing-statistics__summaries'>
              {amountSummaries.map(({ label, value, isTotal }) => (
                <div key={label.id}>
                  <dt>{intl.formatMessage(label)}</dt>
                  <dd>
                    {intl.formatMessage(
                      isTotal ? messages.characters : messages.delta,
                      { count: value },
                    )}
                  </dd>
                </div>
              ))}
            </dl>
          ) : (
            <div className='page-writing-statistics__monthly-report'>
              <strong>
                {intl.formatMessage(messages.monthTotal)} ·{' '}
                {intl.formatMessage(messages.delta, { count: monthlyTotal })}
              </strong>
              <dl>
                {monthlyWeeks.map((week) => (
                  <div key={week.number}>
                    <dt>
                      {intl.formatMessage(messages.weekOfMonth, {
                        number: week.number,
                      })}
                    </dt>
                    <dd>
                      {intl.formatMessage(messages.delta, {
                        count: week.value,
                      })}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          )}
        </section>
      )}
    </div>
  );
};

const Heatmap: React.FC<{
  label: string;
  days: ApiPageWritingStatisticsJSON['days'];
  className: string;
  title: (day: ApiPageWritingStatisticsJSON['days'][number]) => string;
  cellClass: (day: ApiPageWritingStatisticsJSON['days'][number]) => string;
}> = ({ label, days, className, title, cellClass }) => (
  <section className={`page-writing-statistics__map ${className}`}>
    <h3>{label}</h3>
    <div
      className='page-writing-statistics__cells'
      role='img'
      aria-label={label}
    >
      {days.map((day) => (
        <span
          key={day.date}
          className={`page-writing-statistics__cell ${cellClass(day)}`}
          title={title(day)}
        />
      ))}
    </div>
  </section>
);
