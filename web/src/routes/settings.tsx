import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function SettingsPage() {
  return (
    <AppShell title="Settings">
      <PagePlaceholder
        title="Settings"
        description="Profile, password, avatar, and reader preferences."
      />
    </AppShell>
  );
}
