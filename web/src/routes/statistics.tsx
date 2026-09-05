import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function StatisticsPage() {
  return (
    <AppShell title="Statistics">
      <PagePlaceholder
        title="Reading statistics"
        description="Totals, velocity, streaks, and time-of-day patterns for your account."
      />
    </AppShell>
  );
}
