import { useCallback, useEffect, useMemo, useState } from "preact/hooks";
import type { JSX } from "preact";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { FolderIcon, PlusIcon } from "../components/Icons.js";
import { useToast } from "../components/Toast.js";
import { ApiError, foldersApi, toCount } from "../lib/client.js";
import type { FolderNode } from "../lib/api-types.js";
import { Modal } from "../components/secondary/widgets.js";
import {
  ChevronDownIcon,
  ChevronUpIcon,
  PencilIcon,
  TrashIcon,
} from "../components/secondary/icons.js";

export const config = { mode: "app" };

interface FlatFolder {
  folder: FolderNode;
  depth: number;
  siblingIndex: number;
  siblingCount: number;
}

function flattenFolders(folders: FolderNode[]): FlatFolder[] {
  const rows: FlatFolder[] = [];
  const walk = (nodes: FolderNode[], currentDepth: number) => {
    nodes.forEach((node, index) => {
      rows.push({ folder: node, depth: currentDepth, siblingIndex: index, siblingCount: nodes.length });
      walk(node.children, currentDepth + 1);
    });
  };
  walk(folders, 0);
  return rows;
}

function collectIds(folders: FolderNode[]): string[] {
  const ids: string[] = [];
  const walk = (nodes: FolderNode[]) => {
    for (const node of nodes) {
      ids.push(node.id);
      walk(node.children);
    }
  };
  walk(folders);
  return ids;
}

function moveWithinLevel(folders: FolderNode[], folderId: string, direction: -1 | 1): FolderNode[] {
  const index = folders.findIndex((folder) => folder.id === folderId);
  if (index >= 0) {
    const target = index + direction;
    if (target < 0 || target >= folders.length) return folders;
    const next = [...folders];
    [next[index], next[target]] = [next[target], next[index]];
    return next;
  }
  return folders.map((folder) => ({
    ...folder,
    children: moveWithinLevel(folder.children, folderId, direction),
  }));
}

export default function FoldersPage() {
  const { showToast } = useToast();
  const [phase, setPhase] = useState<"loading" | "ready" | "error">("loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [folders, setFolders] = useState<FolderNode[]>([]);
  const [createOpen, setCreateOpen] = useState(false);
  const [createName, setCreateName] = useState("");
  const [createColor, setCreateColor] = useState("#7c9cff");
  const [creating, setCreating] = useState(false);
  const [renameTarget, setRenameTarget] = useState<FolderNode | null>(null);
  const [renameName, setRenameName] = useState("");
  const [renameColor, setRenameColor] = useState("#7c9cff");
  const [renaming, setRenaming] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<FolderNode | null>(null);
  const [deleting, setDeleting] = useState(false);

  const load = useCallback(async () => {
    setPhase("loading");
    try {
      const { folders: tree } = await foldersApi.list();
      setFolders(tree);
      setPhase("ready");
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Failed to load folders");
      setPhase("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const rows = useMemo(() => flattenFolders(folders), [folders]);

  const reorder = async (folderId: string, direction: -1 | 1) => {
    const next = moveWithinLevel(folders, folderId, direction);
    if (next === folders) return;
    setFolders(next);
    try {
      await foldersApi.reorder(collectIds(next));
    } catch (error) {
      showToast({
        title: "Reorder failed",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
      void load();
    }
  };

  const onCreateSubmit = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    const name = createName.trim();
    if (!name || creating) return;
    setCreating(true);
    try {
      await foldersApi.create({ name, color: createColor });
      showToast({ title: "Folder created", message: name, kind: "success" });
      setCreateOpen(false);
      setCreateName("");
      await load();
    } catch (error) {
      showToast({
        title: "Could not create folder",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setCreating(false);
    }
  };

  const onRenameSubmit = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (!renameTarget || renaming) return;
    const name = renameName.trim();
    if (!name) return;
    setRenaming(true);
    try {
      await foldersApi.update(renameTarget.id, { name, color: renameColor });
      showToast({ title: "Folder renamed", message: name, kind: "success" });
      setRenameTarget(null);
      await load();
    } catch (error) {
      showToast({
        title: "Could not rename folder",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setRenaming(false);
    }
  };

  const onDeleteConfirm = async () => {
    if (!deleteTarget || deleting) return;
    setDeleting(true);
    try {
      await foldersApi.remove(deleteTarget.id);
      showToast({ title: "Folder deleted", message: deleteTarget.name, kind: "success" });
      setDeleteTarget(null);
      await load();
    } catch (error) {
      showToast({
        title: "Could not delete folder",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
      setDeleteTarget(null);
    } finally {
      setDeleting(false);
    }
  };

  const deleteFeedCount = deleteTarget ? toCount(deleteTarget.feedCount) : 0;
  const deleteChildCount = deleteTarget ? deleteTarget.children.length : 0;

  return (
    <AppShell
      title="Folders"
      actions={
        <button type="button" class="btn btn-primary btn-sm" onClick={() => setCreateOpen(true)}>
          <PlusIcon size={15} />
          New folder
        </button>
      }
    >
      <div class="page">
        {phase === "loading" ? <SkeletonList rows={4} /> : null}
        {phase === "error" ? (
          <ErrorState title="Folders unavailable" message={errorMessage ?? undefined} onRetry={() => void load()} />
        ) : null}
        {phase === "ready" && folders.length === 0 ? (
          <EmptyState
            icon={<FolderIcon size={24} />}
            title="No folders yet"
            description="Group your feeds into folders to keep your library organized."
            action={
              <button type="button" class="btn btn-primary" onClick={() => setCreateOpen(true)}>
                <PlusIcon size={16} />
                Create your first folder
              </button>
            }
          />
        ) : null}
        {phase === "ready" && folders.length > 0 ? (
          <div class="glass-card">
            {rows.map(({ folder, depth, siblingIndex, siblingCount }) => {
              const feedCount = toCount(folder.feedCount);
              const unreadCount = toCount(folder.unreadCount);
              return (
                <div
                  class="folder-row"
                  style={depth > 0 ? `padding-left: calc(var(--sp-lg) + ${depth * 24}px);` : undefined}
                  key={folder.id}
                >
                  <span class="folder-color-dot" style={folder.color ? `background: ${folder.color};` : undefined} />
                  <FolderIcon size={17} />
                  <span class="folder-name">{folder.name}</span>
                  <span class="folder-meta">
                    <span class="chip">
                      {feedCount} {feedCount === 1 ? "feed" : "feeds"}
                    </span>
                    {unreadCount > 0 ? <span class="chip chip-count">{unreadCount}</span> : null}
                  </span>
                  <span class="folder-actions">
                    <button
                      type="button"
                      class="btn btn-ghost btn-icon btn-sm"
                      disabled={siblingIndex <= 0}
                      aria-label={`Move ${folder.name} up`}
                      onClick={() => void reorder(folder.id, -1)}
                    >
                      <ChevronUpIcon size={15} />
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-icon btn-sm"
                      disabled={siblingIndex >= siblingCount - 1}
                      aria-label={`Move ${folder.name} down`}
                      onClick={() => void reorder(folder.id, 1)}
                    >
                      <ChevronDownIcon size={15} />
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-icon btn-sm"
                      aria-label={`Rename ${folder.name}`}
                      onClick={() => {
                        setRenameTarget(folder);
                        setRenameName(folder.name);
                        setRenameColor(folder.color ?? "#7c9cff");
                      }}
                    >
                      <PencilIcon size={15} />
                    </button>
                    <button
                      type="button"
                      class="btn btn-ghost btn-icon btn-sm"
                      aria-label={`Delete ${folder.name}`}
                      onClick={() => setDeleteTarget(folder)}
                    >
                      <TrashIcon size={15} />
                    </button>
                  </span>
                </div>
              );
            })}
          </div>
        ) : null}
      </div>

      {createOpen ? (
        <Modal title="New folder" onClose={() => setCreateOpen(false)}>
          <form onSubmit={onCreateSubmit}>
            <label class="field">
              <span class="label">Name</span>
              <input
                class="input"
                type="text"
                value={createName}
                onInput={(event) => setCreateName(event.currentTarget.value)}
                maxLength={100}
                autofocus
              />
            </label>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">Color</span>
              <input
                class="input"
                type="color"
                value={createColor}
                onInput={(event) => setCreateColor(event.currentTarget.value)}
                style="height: 44px; padding: 4px;"
              />
            </label>
            <div class="modal-actions">
              <button type="button" class="btn btn-ghost" onClick={() => setCreateOpen(false)}>
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={!createName.trim() || creating}>
                {creating ? <span class="spinner" /> : null}
                Create folder
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {renameTarget ? (
        <Modal title="Rename folder" onClose={() => setRenameTarget(null)}>
          <form onSubmit={onRenameSubmit}>
            <label class="field">
              <span class="label">Name</span>
              <input
                class="input"
                type="text"
                value={renameName}
                onInput={(event) => setRenameName(event.currentTarget.value)}
                maxLength={100}
                autofocus
              />
            </label>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">Color</span>
              <input
                class="input"
                type="color"
                value={renameColor}
                onInput={(event) => setRenameColor(event.currentTarget.value)}
                style="height: 44px; padding: 4px;"
              />
            </label>
            <div class="modal-actions">
              <button type="button" class="btn btn-ghost" onClick={() => setRenameTarget(null)}>
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={!renameName.trim() || renaming}>
                {renaming ? <span class="spinner" /> : null}
                Save changes
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {deleteTarget ? (
        <Modal title="Delete folder" onClose={() => setDeleteTarget(null)}>
          <p class="page-subtitle">
            Delete <strong>{deleteTarget.name}</strong>? This cannot be undone.
          </p>
          {deleteFeedCount > 0 || deleteChildCount > 0 ? (
            <p class="field-hint">
              {deleteFeedCount > 0
                ? `This folder still contains ${deleteFeedCount} ${deleteFeedCount === 1 ? "feed" : "feeds"}. `
                : ""}
              Folders must be empty before they can be deleted — move or remove the
              {deleteFeedCount > 0 ? " feeds" : ""}
              {deleteFeedCount > 0 && deleteChildCount > 0 ? " and " : ""}
              {deleteChildCount > 0 ? `${deleteChildCount} subfolder${deleteChildCount === 1 ? "" : "s"}` : ""} first.
            </p>
          ) : (
            <p class="field-hint">The folder is empty, so its feeds are unaffected.</p>
          )}
          <div class="modal-actions">
            <button type="button" class="btn btn-ghost" onClick={() => setDeleteTarget(null)}>
              Cancel
            </button>
            <button
              type="button"
              class="btn btn-primary"
              style="background: var(--c-error);"
              disabled={deleting || deleteFeedCount > 0 || deleteChildCount > 0}
              onClick={() => void onDeleteConfirm()}
            >
              {deleting ? <span class="spinner" /> : null}
              Delete folder
            </button>
          </div>
        </Modal>
      ) : null}
    </AppShell>
  );
}
