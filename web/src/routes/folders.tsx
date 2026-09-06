import { useCallback, useEffect, useMemo, useRef, useState } from "preact/hooks";
import type { JSX } from "preact";
import { AppShell } from "../components/AppShell.js";
import { EmptyState, ErrorState, SkeletonList } from "../components/states.js";
import { AlertIcon, FileTextIcon, FolderIcon, PlusIcon, RssIcon } from "../components/Icons.js";
import { useToast } from "../components/Toast.js";
import { ApiError, feedsApi, foldersApi } from "../lib/client.js";
import type { ExtractionStats, FeedWithUnread, FolderNode } from "../lib/api-types.js";
import { validateHttpHeaders } from "../lib/feed-headers.js";
import { Modal } from "../components/secondary/widgets.js";
import {
  ChevronDownIcon,
  ChevronUpIcon,
  PencilIcon,
  TrashIcon,
} from "../components/secondary/icons.js";
import "../components/secondary/secondary.css";

export const config = { mode: "app" };

interface FlatFolder {
  folder: FolderNode;
  depth: number;
  parentId: string | null;
  siblingIndex: number;
  siblingCount: number;
}

function flattenFolders(folders: FolderNode[]): FlatFolder[] {
  const rows: FlatFolder[] = [];
  const walk = (nodes: FolderNode[], currentDepth: number, parentId: string | null) => {
    nodes.forEach((node, index) => {
      rows.push({ folder: node, depth: currentDepth, parentId, siblingIndex: index, siblingCount: nodes.length });
      walk(node.children, currentDepth + 1, node.id);
    });
  };
  walk(folders, 0, null);
  return rows;
}

function folderPaths(folders: FolderNode[], prefix: string[] = []): Array<{ id: string; path: string }> {
  const rows: Array<{ id: string; path: string }> = [];
  for (const node of folders) {
    const path = [...prefix, node.name].join(" / ");
    rows.push({ id: node.id, path });
    rows.push(...folderPaths(node.children, [...prefix, node.name]));
  }
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

// Drag-and-drop reordering: moves dragId to targetId's slot. Both must live
// in the same sibling level (same parent) — cross-level moves stay on the
// folder select. Returns the input unchanged for an invalid or no-op drop.
function moveFolderTo(folders: FolderNode[], dragId: string, targetId: string): FolderNode[] {
  const dragIndex = folders.findIndex((folder) => folder.id === dragId);
  const targetIndex = folders.findIndex((folder) => folder.id === targetId);
  if (dragIndex >= 0 || targetIndex >= 0) {
    if (dragIndex < 0 || targetIndex < 0 || dragIndex === targetIndex) return folders;
    const next = [...folders];
    const [moved] = next.splice(dragIndex, 1);
    next.splice(targetIndex, 0, moved);
    return next;
  }
  return folders.map((folder) => ({
    ...folder,
    children: moveFolderTo(folder.children, dragId, targetId),
  }));
}

function feedDisplayTitle(feed: FeedWithUnread): string {
  return feed.customTitle || feed.title;
}

function feedIsFailing(feed: FeedWithUnread): boolean {
  return feed.errorCount > 0 || Boolean(feed.lastFetchError);
}

function feedPageStatus(feed: FeedWithUnread): string | null {
  const settings = feed.settings;
  if (!settings || typeof settings !== "object") return null;
  const status = (settings as Record<string, unknown>).pageStatus;
  return typeof status === "string" ? status : null;
}

// Structured pageStatus (feeds.settings JSONB), not lastFetchError string
// matching: both miss states keep the last good items.
function feedKeptLastGood(feed: FeedWithUnread): boolean {
  if (feed.sourceType !== "page") return false;
  const status = feedPageStatus(feed);
  return status === "selector-miss" || status === "fetch-error";
}

// Amber only when failures are more than noise: 3+ absolute, or over a fifth
// of the scanned window.
function extractionFailing(stats: ExtractionStats): boolean {
  if (stats.failed <= 0) return false;
  return stats.failed >= 3 || (stats.scanned > 0 && stats.failed / stats.scanned > 0.2);
}

export default function FoldersPage() {
  const { showToast } = useToast();
  const [phase, setPhase] = useState<"loading" | "ready" | "error">("loading");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [folders, setFolders] = useState<FolderNode[]>([]);
  const [feeds, setFeeds] = useState<FeedWithUnread[]>([]);
  const [movingFeedId, setMovingFeedId] = useState<string | null>(null);
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
  const [togglingFullTextId, setTogglingFullTextId] = useState<string | null>(null);
  const [extractionStats, setExtractionStats] = useState<Map<string, ExtractionStats>>(new Map());
  const extractionRequestedRef = useRef<Set<string>>(new Set());
  const [editTarget, setEditTarget] = useState<FeedWithUnread | null>(null);
  const [editTitle, setEditTitle] = useState("");
  const [editInterval, setEditInterval] = useState("30");
  const [editCookie, setEditCookie] = useState("");
  const [editRows, setEditRows] = useState<Array<{ key: string; value: string }>>([]);
  const [editError, setEditError] = useState<string | null>(null);
  const [editSaving, setEditSaving] = useState(false);

  // Headers live on feed detail (the list omits them — they can carry the
  // owner's cookies), so the dialog fetches them on open.
  const openEditDialog = (feed: FeedWithUnread) => {
    setEditTarget(feed);
    setEditTitle(feed.customTitle ?? "");
    setEditInterval(String(feed.updateInterval ?? 30));
    setEditCookie("");
    setEditRows([]);
    setEditError(null);
    feedsApi
      .get(feed.id)
      .then((detail) => {
        const headers = detail.feed.httpHeaders ?? {};
        const rows: Array<{ key: string; value: string }> = [];
        for (const [key, value] of Object.entries(headers)) {
          if (key.toLowerCase() === "cookie") {
            setEditCookie(value);
          } else {
            rows.push({ key, value });
          }
        }
        setEditRows(rows);
      })
      .catch(() => undefined);
  };

  const onEditSubmit = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (!editTarget || editSaving) return;
    setEditError(null);

    const interval = parseInt(editInterval, 10);
    if (!Number.isFinite(interval) || interval < 5 || interval > 1440) {
      setEditError("Update interval must be between 5 and 1440 minutes");
      return;
    }

    const headerObject: Record<string, string> = {};
    for (const row of editRows) {
      const key = row.key.trim();
      if (key) headerObject[key] = row.value;
    }
    const cookie = editCookie.trim();
    if (cookie) headerObject["Cookie"] = cookie;

    const validated = validateHttpHeaders(headerObject);
    if (!validated.ok) {
      setEditError(validated.error);
      return;
    }

    const hasHeaders = Object.keys(validated.value).length > 0;

    setEditSaving(true);
    try {
      await feedsApi.update(editTarget.id, {
        customTitle: editTitle.trim(),
        updateInterval: interval,
        httpHeaders: hasHeaders ? validated.value : null,
      });
      showToast({ title: "Feed updated", message: feedDisplayTitle(editTarget), kind: "success" });
      setEditTarget(null);
      await load();
    } catch (error) {
      setEditError(error instanceof ApiError ? error.message : "Could not save the feed");
    } finally {
      setEditSaving(false);
    }
  };

  // Extraction health lives on feed detail, not the list (no N+1 on load).
  // Fetched lazily on row hover/focus — once per feed per page session.
  const ensureExtractionStats = useCallback((feed: FeedWithUnread) => {
    if (!feed.fullTextEnabled || extractionRequestedRef.current.has(feed.id)) return;
    extractionRequestedRef.current.add(feed.id);
    feedsApi
      .get(feed.id)
      .then((detail) => {
        const stats = detail.extractionStats;
        if (!stats) return;
        setExtractionStats((current) => {
          const next = new Map(current);
          next.set(feed.id, stats);
          return next;
        });
      })
      .catch(() => {
        extractionRequestedRef.current.delete(feed.id);
      });
  }, []);

  const load = useCallback(async () => {
    setPhase("loading");
    try {
      const [foldersResponse, feedsResponse] = await Promise.all([foldersApi.list(), feedsApi.list()]);
      setFolders(foldersResponse.folders);
      setFeeds(feedsResponse.feeds);
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
  const rowsById = useMemo(() => new Map(rows.map((row) => [row.folder.id, row])), [rows]);
  const feedGroups = useMemo(() => {
    const grouped = new Map<string, FeedWithUnread[]>();
    const unfiled: FeedWithUnread[] = [];
    for (const feed of feeds) {
      if (feed.folderId) {
        const list = grouped.get(feed.folderId) ?? [];
        list.push(feed);
        grouped.set(feed.folderId, list);
      } else {
        unfiled.push(feed);
      }
    }
    return { grouped, unfiled };
  }, [feeds]);
  const folderOptions = useMemo(() => folderPaths(folders), [folders]);

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

  // HTML5 drag-and-drop alongside the up/down buttons (keyboard fallback).
  // Same-level drops only — see moveFolderTo.
  const [dragFolderId, setDragFolderId] = useState<string | null>(null);
  const [dropTargetId, setDropTargetId] = useState<string | null>(null);

  const canDropOn = (targetId: string): boolean => {
    if (dragFolderId === null || dragFolderId === targetId) return false;
    return rowsById.get(dragFolderId)?.parentId === rowsById.get(targetId)?.parentId;
  };

  const onFolderDrop = async (targetId: string) => {
    const sourceId = dragFolderId;
    setDragFolderId(null);
    setDropTargetId(null);
    if (!sourceId || !canDropOn(targetId)) return;
    const next = moveFolderTo(folders, sourceId, targetId);
    if (collectIds(next).join("\n") === collectIds(folders).join("\n")) return;
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

  const moveFeed = async (feed: FeedWithUnread, folderId: string) => {
    if (movingFeedId) return;
    setMovingFeedId(feed.id);
    try {
      await feedsApi.update(feed.id, { folderId: folderId || null });
      showToast({
        title: folderId ? `Moved to folder` : "Removed from folder",
        message: feedDisplayTitle(feed),
        kind: "success",
      });
      await load();
    } catch (error) {
      showToast({
        title: "Could not move feed",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setMovingFeedId(null);
    }
  };

  const toggleFullText = async (feed: FeedWithUnread) => {
    if (togglingFullTextId) return;
    const next = !feed.fullTextEnabled;
    setTogglingFullTextId(feed.id);
    setFeeds((current) => current.map((item) => (item.id === feed.id ? { ...item, fullTextEnabled: next } : item)));
    try {
      await feedsApi.update(feed.id, { fullTextEnabled: next });
      showToast({
        title: next ? "Full text enabled" : "Full text disabled",
        message: next
          ? `${feedDisplayTitle(feed)}. New articles fetch the full page body.`
          : feedDisplayTitle(feed),
        kind: "success",
      });
    } catch (error) {
      setFeeds((current) => current.map((item) => (item.id === feed.id ? { ...item, fullTextEnabled: !next } : item)));
      showToast({
        title: "Could not change full text",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setTogglingFullTextId(null);
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

  const renderFeedRow = (feed: FeedWithUnread, depth: number) => {
    const unread = feed.unreadCount;
    const failing = feedIsFailing(feed);
    const keptLastGood = feedKeptLastGood(feed);
    const stats = extractionStats.get(feed.id);
    const extractionDegraded = stats ? extractionFailing(stats) : false;
    return (
      <div
        class="folder-feed-row"
        style={`padding-left: calc(var(--sp-lg) + ${depth * 24}px);`}
        key={feed.id}
        onMouseEnter={() => ensureExtractionStats(feed)}
        onFocus={() => ensureExtractionStats(feed)}
      >
        <span class="folder-feed-icon">
          {feed.favicon ? <img src={feed.favicon} alt="" loading="lazy" /> : null}
          <span class={`folder-feed-fallback${feed.favicon ? " folder-feed-fallback-hidden" : ""}`}>
            {feedDisplayTitle(feed).trim().charAt(0).toUpperCase() || "?"}
          </span>
        </span>
        <span class="folder-feed-title" title={feedDisplayTitle(feed)}>{feedDisplayTitle(feed)}</span>
        {feed.sourceType === "page" ? <span class="folder-feed-flag" title="Page feed">Page</span> : null}
        {feed.fullTextEnabled ? (
          <span class="folder-feed-flag folder-feed-flag-full-text" title="Full text enabled">Full text</span>
        ) : null}
        {failing ? (
          <span
            class={`folder-feed-warning${keptLastGood ? " folder-feed-warning-kept" : ""}`}
            role="img"
            aria-label={keptLastGood ? "Page feed not updating; kept the last good items" : "Feed failed to update recently"}
            title={
              keptLastGood
                ? `Kept last good items — ${feed.lastFetchError || "page feed did not update"}`
                : feed.lastFetchError || "This feed failed to update recently"
            }
          >
            <AlertIcon size={14} />
          </span>
        ) : null}
        {extractionDegraded && stats ? (
          <span
            class="folder-feed-warning"
            role="img"
            aria-label={`Full-text extraction failing on ${stats.failed} of ${stats.scanned} recent articles`}
            title={`Full-text extraction failing on ${stats.failed} of ${stats.scanned} recent articles`}
          >
            <AlertIcon size={14} />
          </span>
        ) : null}
        {unread > 0 ? <span class="chip chip-count">{unread}</span> : null}
        <span class="folder-feed-actions">
          <button
            type="button"
            class="btn btn-ghost btn-icon btn-sm"
            aria-label={`Edit ${feedDisplayTitle(feed)}`}
            title="Edit feed (title, interval, headers)"
            onClick={() => openEditDialog(feed)}
          >
            <PencilIcon size={15} />
          </button>
          {feed.sourceType === "page" ? null : (
            <button
              type="button"
              class={`btn btn-ghost btn-icon btn-sm folder-feed-action-toggle${feed.fullTextEnabled ? " is-on" : ""}`}
              disabled={togglingFullTextId !== null}
              aria-pressed={feed.fullTextEnabled}
              aria-label={`Toggle full text for ${feedDisplayTitle(feed)}`}
              title={feed.fullTextEnabled ? "Full text enabled. Click to disable." : "Full text disabled. Click to enable."}
              onClick={() => void toggleFullText(feed)}
            >
              <FileTextIcon size={15} />
            </button>
          )}
          <label class="folder-feed-move-label">
            <span class="folder-feed-move-caption">Folder</span>
            <select
              class="input feed-move-select"
              value={feed.folderId ?? ""}
              disabled={movingFeedId !== null}
              aria-label={`Folder for ${feedDisplayTitle(feed)}`}
              onChange={(event) => void moveFeed(feed, event.currentTarget.value)}
            >
              <option value="">No folder</option>
              {folderOptions.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.path}
                </option>
              ))}
            </select>
          </label>
        </span>
      </div>
    );
  };

  const deleteFeedCount = deleteTarget ? deleteTarget.feedCount : 0;
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
        {phase === "ready" && folders.length === 0 && feeds.length === 0 ? (
          <EmptyState
            icon={<FolderIcon size={24} />}
            title="No folders yet"
            description="Group your feeds into folders to keep your library organized. Subscribe to a feed first, then file it here."
            action={
              <>
                <button type="button" class="btn btn-primary" onClick={() => setCreateOpen(true)}>
                  <PlusIcon size={16} />
                  Create your first folder
                </button>
                <a class="btn btn-secondary" href="/discover">
                  <RssIcon size={16} />
                  Find feeds
                </a>
              </>
            }
          />
        ) : null}
        {phase === "ready" && (folders.length > 0 || feeds.length > 0) ? (
          <div class="glass-card folder-listing">
            {rows.map(({ folder, depth, siblingIndex, siblingCount }) => {
              const feedCount = folder.feedCount;
              const unreadCount = folder.unreadCount;
              const folderFeeds = feedGroups.grouped.get(folder.id) ?? [];
              return (
                <div key={folder.id}>
                  <div
                    class={`folder-row${dragFolderId === folder.id ? " folder-row-dragging" : ""}${dropTargetId === folder.id ? " folder-row-drop-target" : ""}`}
                    style={depth > 0 ? `padding-left: calc(var(--sp-lg) + ${depth * 24}px);` : undefined}
                    title="Drag to reorder within this level"
                    draggable={true}
                    onDragStart={(event: JSX.TargetedDragEvent<HTMLDivElement>) => {
                      setDragFolderId(folder.id);
                      if (!event.dataTransfer) return;
                      event.dataTransfer.effectAllowed = "move";
                      event.dataTransfer.setData("text/plain", folder.id);
                    }}
                    onDragOver={(event: JSX.TargetedDragEvent<HTMLDivElement>) => {
                      if (!canDropOn(folder.id) || !event.dataTransfer) return;
                      event.preventDefault();
                      event.dataTransfer.dropEffect = "move";
                      setDropTargetId(folder.id);
                    }}
                    onDragLeave={() => setDropTargetId((current) => (current === folder.id ? null : current))}
                    onDrop={(event: JSX.TargetedDragEvent<HTMLDivElement>) => {
                      event.preventDefault();
                      void onFolderDrop(folder.id);
                    }}
                    onDragEnd={() => {
                      setDragFolderId(null);
                      setDropTargetId(null);
                    }}
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
                  {folderFeeds.map((feed) => renderFeedRow(feed, depth + 1))}
                </div>
              );
            })}
            {feedGroups.unfiled.length > 0 ? (
              <div>
                <div class="folder-row folder-row-unfiled">
                  <span class="folder-color-dot folder-dot-none" />
                  <RssIcon size={16} />
                  <span class="folder-name">No folder</span>
                  <span class="folder-meta">
                    <span class="chip">
                      {feedGroups.unfiled.length} {feedGroups.unfiled.length === 1 ? "feed" : "feeds"}
                    </span>
                  </span>
                </div>
                {feedGroups.unfiled.map((feed) => renderFeedRow(feed, 1))}
              </div>
            ) : null}
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

      {editTarget ? (
        <Modal title={`Edit ${feedDisplayTitle(editTarget)}`} onClose={() => setEditTarget(null)}>
          <form onSubmit={onEditSubmit}>
            <label class="field">
              <span class="label">Custom title</span>
              <input
                class="input"
                type="text"
                value={editTitle}
                onInput={(event) => setEditTitle(event.currentTarget.value)}
                maxLength={500}
                placeholder={editTarget.title}
              />
            </label>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">Update interval (minutes)</span>
              <input
                class="input"
                type="number"
                min={5}
                max={1440}
                step={1}
                value={editInterval}
                onInput={(event) => setEditInterval(event.currentTarget.value)}
              />
              <span class="field-hint">How often the worker refreshes this feed (5 to 1440 minutes).</span>
            </label>
            <div class="field" style="margin-top: var(--sp-md);">
              <span class="label">HTTP headers</span>
              <label class="field">
                <span class="label">Cookie (quick paste)</span>
                <textarea
                  class="input"
                  value={editCookie}
                  onInput={(event) => setEditCookie(event.currentTarget.value)}
                  placeholder="session=...; subscriber=..."
                  spellcheck={false}
                />
              </label>
              <div class="feed-edit-header-rows">
                {editRows.map((row, index) => (
                  <div class="feed-edit-header-row" key={index}>
                    <input
                      class="input"
                      type="text"
                      value={row.key}
                      placeholder="Header (e.g. X-Token)"
                      spellcheck={false}
                      onInput={(event) => {
                        const value = event.currentTarget.value;
                        setEditRows((current) => current.map((r, i) => (i === index ? { ...r, key: value } : r)));
                      }}
                    />
                    <input
                      class="input"
                      type="text"
                      value={row.value}
                      placeholder="Value"
                      spellcheck={false}
                      onInput={(event) => {
                        const value = event.currentTarget.value;
                        setEditRows((current) => current.map((r, i) => (i === index ? { ...r, value } : r)));
                      }}
                    />
                    <button
                      type="button"
                      class="btn btn-ghost btn-icon btn-sm"
                      aria-label={`Remove header ${row.key || index + 1}`}
                      onClick={() => setEditRows((current) => current.filter((_, i) => i !== index))}
                    >
                      <TrashIcon size={15} />
                    </button>
                  </div>
                ))}
              </div>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                onClick={() => setEditRows((current) => [...current, { key: "", value: "" }])}
              >
                Add header
              </button>
              <span class="field-hint">
                Sent with every fetch of this feed — paste your subscription cookie so paywalled content you pay for downloads in full.
                Allowed: Cookie, User-Agent, Referer, Accept, Accept-Language, Authorization, and X-* headers.
              </span>
            </div>
            {editError ? <p class="field-error">{editError}</p> : null}
            <div class="modal-actions">
              <button type="button" class="btn btn-ghost" onClick={() => setEditTarget(null)}>
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={editSaving}>
                {editSaving ? <span class="spinner" /> : null}
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
