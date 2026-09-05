import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function AnalyticsPage() {
  return (
    <AppShell title="Analytics">
      <PagePlaceholder
        title="Reading analytics"
        description="Habits, preferences, and engagement signals drawn from your real reading history."
      />
    </AppShell>
  );
}
