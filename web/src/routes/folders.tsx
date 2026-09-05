import { AppShell, PagePlaceholder } from "../components/AppShell.js";

export const config = { mode: "app" };

export default function FoldersPage() {
  return (
    <AppShell title="Folders">
      <PagePlaceholder
        title="Organize with folders"
        description="Group feeds into folders and keep your library tidy."
      />
    </AppShell>
  );
}
