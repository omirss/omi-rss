import { useCallback, useEffect, useMemo, useState } from "preact/hooks";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, Skeleton } from "../components/states.js";
import { StatisticsIcon } from "../components/Icons.js";
import { toCount, statsApi } from "../lib/client.js";
import type { StatsHistory, StatsOverview } from "../lib/api-types.js";
import { Section, StatCard, StatGrid, VBarChart, formatDayShort } from "../components/secondary/widgets.js";

export const config = { mode: "app" };

type Phase = "loading" | "ready" | "error";

const HISTORY_DAYS = 30;

function buildHistoryItems(history: StatsHistory | null) {
  if (!history) return [];
  const counts = new Map(history.data.map((entry) => [entry.period, toCount(entry.count)]));
  const items: Array<{ label: string; count: number }> = [];
  const start = new Date(history.startDate);
  const end = new Date(history.endDate);
  for (let date = new Date(start); date <= end && items.length < HISTORY_DAYS * 2; date.setDate(date.getDate() + 1)) {
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
    items.push({
      label: date.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      count: counts.get(key) ?? 0,
    });
  }
  return items;
}

export default function StatisticsPage() {
  const [phase, setPhase] = useState<Phase>("loading");
  const [overview, setOverview] = useState<StatsOverview | null>(null);
  const [history, setHistory] = useState<StatsHistory | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  const load = useCallback(async () => {
    setPhase("loading");
    try {
      const [overviewData, historyData] = await Promise.all([
        statsApi.overview(),
        statsApi.history({ period: "day" }),
      ]);
      setOverview(overviewData);
      setHistory(historyData);
      setPhase("ready");
    } catch {
      setPhase("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  const totals = overview?.totals;
  const historyItems = useMemo(() => buildHistoryItems(history), [history]);
  const historyAxis: [string, string] | undefined =
    historyItems.length > 0 ? [historyItems[0].label, historyItems[historyItems.length - 1].label] : undefined;
  const totalRead = totals ? toCount(totals.readArticles) : 0;
  const totalArticles = totals ? toCount(totals.totalArticles) : 0;
  const unread = Math.max(0, totalArticles - totalRead);
  const hasActivity = totals !== undefined && (totalArticles > 0 || toCount(totals.totalFeeds) > 0);
  const streak = overview?.readingStreak;

  return (
    <AppShell title="Statistics">
      <div class="page">
        {phase === "loading" ? (
          <div class="glass-card sec-card">
            <div class="stat-grid">
              <Skeleton variant="block" />
              <Skeleton variant="block" />
              <Skeleton variant="block" />
              <Skeleton variant="block" />
            </div>
            <Skeleton width="60%" />
            <Skeleton width="80%" />
          </div>
        ) : null}

        {phase === "error" ? (
          <ErrorState
            title="Statistics unavailable"
            message="Your reading statistics could not be loaded right now."
            onRetry={() => setReloadKey((key) => key + 1)}
          />
        ) : null}

        {phase === "ready" && !hasActivity ? (
          <EmptyState
            icon={<StatisticsIcon size={24} />}
            title="No statistics yet"
            description="Subscribe to feeds and read a few articles — totals, history, and streaks will appear here."
          />
        ) : null}

        {phase === "ready" && hasActivity && totals && overview ? (
          <>
            <Section title="Totals">
              <StatGrid>
                <StatCard value={`${toCount(totals.totalFeeds)}`} label="Feeds" hint={`${toCount(totals.totalFolders)} folders`} />
                <StatCard value={`${totalArticles}`} label="Articles" hint="Across all feeds" />
                <StatCard value={`${totalRead}`} label="Read" hint={`${totals.readPercentage}% of library`} />
                <StatCard value={`${unread}`} label="Unread" />
                <StatCard value={`${toCount(totals.starredArticles)}`} label="Starred" />
                <StatCard value={`${overview.velocity.averagePerDay}`} label="Avg. articles per day" hint="Last 30 days" />
                <StatCard
                  value={`${streak ? streak.currentStreak : 0} day${streak && streak.currentStreak === 1 ? "" : "s"}`}
                  label="Current streak"
                  hint={streak ? `Longest: ${streak.longestStreak} days` : undefined}
                />
              </StatGrid>
            </Section>

            <Section title="Reading history">
              <div class="glass-card sec-card">
                <VBarChart items={historyItems} axisLabels={historyAxis} />
                <p class="stat-hint">Articles read per day over the last {historyItems.length} days.</p>
              </div>
            </Section>

            <Section title="Top feeds">
              <div class="glass-card sec-card">
                {overview.topFeeds.length === 0 ? (
                  <p class="stat-hint">Nothing read yet — your most-read feeds will rank here.</p>
                ) : (
                  <table class="sec-table">
                    <thead>
                      <tr>
                        <th style="width: 40px;">#</th>
                        <th>Feed</th>
                        <th style="width: 120px; text-align: right;">Articles read</th>
                      </tr>
                    </thead>
                    <tbody>
                      {overview.topFeeds.map((feed, index) => (
                        <tr key={feed.feedId}>
                          <td class="sec-table-rank">{index + 1}</td>
                          <td>
                            <span class="sec-table-feed">
                              {feed.feedFavicon ? (
                                <img class="sec-table-favicon" src={feed.feedFavicon} alt="" />
                              ) : null}
                              <span class="sec-table-feed-name">{feed.feedTitle}</span>
                            </span>
                          </td>
                          <td class="sec-table-count" style="text-align: right;">
                            {toCount(feed.readCount)}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </Section>

            {streak && streak.lastReadDate ? (
              <Section title="Habits">
                <div class="glass-card sec-card">
                  <StatGrid>
                    <StatCard value={`${streak.currentStreak}`} label="Current streak (days)" />
                    <StatCard value={`${streak.longestStreak}`} label="Longest streak (days)" />
                    <StatCard
                      value={new Date(streak.lastReadDate).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                      })}
                      label="Last read"
                      hint={formatDayShort(
                        new Date(streak.lastReadDate).toLocaleDateString(undefined, { weekday: "long" }),
                      )}
                    />
                  </StatGrid>
                </div>
              </Section>
            ) : null}
          </>
        ) : null}
      </div>
    </AppShell>
  );
}
