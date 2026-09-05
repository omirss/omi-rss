import { useCallback, useEffect, useState } from "preact/hooks";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, Skeleton } from "../components/states.js";
import { AnalyticsIcon, InfoIcon } from "../components/Icons.js";
import { analyticsApi } from "../lib/client.js";
import type { AnalyticsPayload, AnalyticsStreaks } from "../lib/api-types.js";
import {
  HBarList,
  Meter,
  Section,
  StatCard,
  StatGrid,
  VBarChart,
  formatDayShort,
  formatHour,
  formatMinutes,
} from "../components/secondary/widgets.js";
import {
  FlameIcon,
  SparkIcon,
  TrendDownIcon,
  TrendFlatIcon,
  TrendUpIcon,
} from "../components/secondary/icons.js";

export const config = { mode: "app" };

type Timeframe = "week" | "month";
type Tab = "overview" | "patterns" | "insights";

type Phase = "loading" | "ready" | "error";

const DAILY_HISTORY_DAYS = 30;

function streakHistoryItems(streaks: AnalyticsStreaks | null) {
  if (!streaks) return [];
  return [...streaks.dailyHistory]
    .sort((a, b) => (a.date < b.date ? -1 : 1))
    .slice(-DAILY_HISTORY_DAYS)
    .map((entry) => ({
      label: new Date(`${entry.date}T00:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      count: entry.articlesRead,
    }));
}

export default function AnalyticsPage() {
  const [timeframe, setTimeframe] = useState<Timeframe>("week");
  const [tab, setTab] = useState<Tab>("overview");
  const [phase, setPhase] = useState<Phase>("loading");
  const [payload, setPayload] = useState<AnalyticsPayload | null>(null);
  const [streaks, setStreaks] = useState<AnalyticsStreaks | null>(null);

  const load = useCallback(
    async (current: Timeframe) => {
      setPhase("loading");
      try {
        const [summary, streakInfo] = await Promise.all([
          analyticsApi.summary(current),
          analyticsApi.streaks(),
        ]);
        setPayload(summary);
        setStreaks(streakInfo);
        setPhase("ready");
      } catch {
        setPhase("error");
      }
    },
    [],
  );

  useEffect(() => {
    void load(timeframe);
  }, [timeframe, load]);

  const onTimeframeChange = (next: Timeframe) => {
    if (next === timeframe) return;
    setTimeframe(next);
  };

  const reading = payload?.reading;
  const preferences = payload?.preferences;
  const patterns = payload?.patterns;
  const engagement = payload?.engagement;
  const hasData = phase === "ready" && reading !== undefined && reading.totalArticlesRead > 0;

  const weeklyItems =
    patterns?.weeklyDistribution.map((entry) => ({
      label: formatDayShort(entry.day),
      count: entry.count,
    })) ?? [];
  const hourlyItems =
    patterns?.dailyDistribution.map((entry) => ({
      label: formatHour(entry.hour),
      count: entry.count,
    })) ?? [];
  const trendItems =
    patterns?.monthlyTrend.map((entry) => ({
      label: new Date(`${entry.date}T00:00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      count: entry.count,
    })) ?? [];
  const trendAxis: [string, string] | undefined = trendItems.length
    ? [trendItems[0].label, trendItems[trendItems.length - 1].label]
    : undefined;

  return (
    <AppShell
      title="Analytics"
      actions={
        <div class="segmented" role="tablist" aria-label="Timeframe">
          {(["week", "month"] as const).map((option) => (
            <button
              key={option}
              type="button"
              role="tab"
              aria-selected={timeframe === option}
              class={`segmented-item${timeframe === option ? " segmented-item-active" : ""}`}
              onClick={() => onTimeframeChange(option)}
            >
              {option === "week" ? "Week" : "Month"}
            </button>
          ))}
        </div>
      }
    >
      <div class="page">
        <div class="segmented" role="tablist" aria-label="Analytics view">
          {(
            [
              ["overview", "Overview"],
              ["patterns", "Patterns"],
              ["insights", "Insights"],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={tab === value}
              class={`segmented-item${tab === value ? " segmented-item-active" : ""}`}
              onClick={() => setTab(value)}
            >
              {label}
            </button>
          ))}
        </div>

        {phase === "loading" ? (
          <div class="glass-card sec-card">
            <Skeleton width="30%" />
            <div class="stat-grid">
              <Skeleton variant="block" />
              <Skeleton variant="block" />
              <Skeleton variant="block" />
              <Skeleton variant="block" />
            </div>
            <Skeleton width="70%" />
          </div>
        ) : null}

        {phase === "error" ? (
          <ErrorState
            title="Analytics unavailable"
            message="Your reading analytics could not be loaded right now."
            onRetry={() => void load(timeframe)}
          />
        ) : null}

        {phase === "ready" && !hasData ? (
          <EmptyState
            icon={<AnalyticsIcon size={24} />}
            title="No reading data yet"
            description="Read a few articles and your habits, preferences, and engagement will show up here."
          />
        ) : null}

        {phase === "ready" && hasData && reading && preferences && patterns && engagement ? (
          <>
            {tab === "overview" ? (
              <>
                <Section title={`Reading — last ${timeframe === "week" ? "7 days" : "30 days"}`}>
                  <StatGrid>
                    <StatCard value={`${reading.totalArticlesRead}`} label="Articles read" />
                    <StatCard value={formatMinutes(reading.totalReadingTime)} label="Reading time" />
                    <StatCard value={formatMinutes(reading.averageReadingTime)} label="Avg. time per article" />
                    <StatCard value={reading.articlesPerDay.toFixed(1)} label="Articles per day" hint="Average" />
                    <StatCard value={formatHour(reading.mostActiveHour)} label="Most active hour" />
                    <StatCard value={formatDayShort(reading.mostActiveDay)} label="Most active day" hint={reading.mostActiveDay} />
                  </StatGrid>
                </Section>

                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: var(--sp-lg);">
                  <Section title="Streaks">
                    <div class="glass-card sec-card streak-widget">
                      <div class="streak-days">
                        <div class="streak-day">
                          <span class="streak-day-value">{streaks?.currentStreak ?? reading.readingStreak}</span>
                          <span class="streak-day-label">Current streak (days)</span>
                        </div>
                        <div class="streak-day">
                          <span class="streak-day-value">{streaks?.longestStreak ?? reading.longestStreak}</span>
                          <span class="streak-day-label">Longest streak (days)</span>
                        </div>
                      </div>
                      <VBarChart items={streakHistoryItems(streaks)} />
                    </div>
                  </Section>

                  <Section title="Engagement">
                    <div class="glass-card sec-card">
                      <StatGrid>
                        <StatCard value={`${engagement.averageTimePerParagraph.toFixed(1)}m`} label="Avg. time per paragraph" />
                        <StatCard value={`${engagement.bookmarkRate}%`} label="Bookmark rate" hint="Starred vs. read" />
                      </StatGrid>
                      <div>
                        <div class="hbar-meta" style="margin-bottom: var(--sp-xs);">
                          <span class="hbar-name">Interaction score</span>
                          <span class="hbar-count">{engagement.interactionScore}/100</span>
                        </div>
                        <Meter percent={engagement.interactionScore} />
                      </div>
                    </div>
                  </Section>
                </div>

                <Section title="Top sources">
                  <div class="glass-card sec-card">
                    <HBarList
                      items={preferences.topSources.map((source) => ({
                        name: source.source,
                        count: source.count,
                        detail: `${source.count} read`,
                      }))}
                      emptyMessage="No sources read in this timeframe yet."
                    />
                  </div>
                </Section>

                <Section title="Top categories">
                  <div class="glass-card sec-card">
                    <HBarList
                      items={preferences.topCategories.map((category) => ({
                        name: category.category,
                        count: category.count,
                        detail: `${category.percentage}%`,
                      }))}
                      emptyMessage="Your feeds do not publish categories yet."
                    />
                  </div>
                </Section>
              </>
            ) : null}

            {tab === "patterns" ? (
              <>
                <Section title="Reading by hour">
                  <div class="glass-card sec-card">
                    <VBarChart items={hourlyItems} axisLabels={["12 AM", "11 PM"]} />
                  </div>
                </Section>

                <Section title="Reading by day of week">
                  <div class="glass-card sec-card">
                    <VBarChart items={weeklyItems} axisLabels={weeklyItems.length > 0 ? [weeklyItems[0].label, weeklyItems[weeklyItems.length - 1].label] : undefined} />
                  </div>
                </Section>

                <Section title="Last 30 days">
                  <div class="glass-card sec-card">
                    <VBarChart items={trendItems} axisLabels={trendAxis} />
                  </div>
                </Section>

                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: var(--sp-lg);">
                  <Section title="Category trends">
                    <div class="glass-card sec-card">
                      {patterns.categoryTrends.length === 0 ? (
                        <p class="stat-hint">No category trends yet — your feeds do not publish categories.</p>
                      ) : (
                        <div style="display: flex; flex-wrap: wrap; gap: var(--sp-sm);">
                          {patterns.categoryTrends.map((trend) => (
                            <span class="chip" key={trend.category}>
                              {trend.trend === "rising" ? (
                                <TrendUpIcon size={14} class="trend-chip-up" />
                              ) : trend.trend === "falling" ? (
                                <TrendDownIcon size={14} class="trend-chip-down" />
                              ) : (
                                <TrendFlatIcon size={14} class="trend-chip-flat" />
                              )}
                              {trend.category}
                              <span class={trend.trend === "rising" ? "trend-chip-up" : trend.trend === "falling" ? "trend-chip-down" : "trend-chip-flat"}>
                                {trend.change > 0 ? "+" : ""}
                                {trend.change}%
                              </span>
                            </span>
                          ))}
                        </div>
                      )}
                      <span class="chip chip-active">
                        <FlameIcon size={14} />
                        Reading velocity: {patterns.velocityTrend}
                      </span>
                    </div>
                  </Section>

                  <Section title="Top keywords">
                    <div class="glass-card sec-card">
                      {preferences.topKeywords.length === 0 ? (
                        <p class="stat-hint">No keywords detected in this timeframe yet.</p>
                      ) : (
                        <div style="display: flex; flex-wrap: wrap; gap: var(--sp-sm);">
                          {preferences.topKeywords.map((keyword) => (
                            <span class="chip" key={keyword.keyword}>
                              <SparkIcon size={13} />
                              {keyword.keyword}
                              <span class="chip-count">{keyword.frequency}</span>
                            </span>
                          ))}
                        </div>
                      )}
                      <p class="stat-hint">
                        Reading speed: {preferences.readingSpeed} words/min — preferred length: {preferences.preferredLength}.
                      </p>
                    </div>
                  </Section>
                </div>

                <Section title="Top authors">
                  <div class="glass-card sec-card">
                    <HBarList
                      items={preferences.topAuthors.map((author) => ({
                        name: author.author,
                        count: author.count,
                        detail: `${author.articles} read`,
                      }))}
                      emptyMessage="No bylined articles read in this timeframe yet."
                    />
                  </div>
                </Section>
              </>
            ) : null}

            {tab === "insights" ? (
              <Section title="Insights">
                {payload && payload.insights.length > 0 ? (
                  <ul class="insight-list">
                    {payload.insights.map((insight) => (
                      <li class="insight-item" key={insight}>
                        <span class="insight-item-icon">
                          <InfoIcon size={17} />
                        </span>
                        {insight}
                      </li>
                    ))}
                  </ul>
                ) : (
                  <div class="glass-card sec-card">
                    <EmptyState
                      icon={<AnalyticsIcon size={24} />}
                      title="No insights yet"
                      description="Keep reading — insights appear once there is enough history to draw from."
                    />
                  </div>
                )}
              </Section>
            ) : null}
          </>
        ) : null}
      </div>
    </AppShell>
  );
}
