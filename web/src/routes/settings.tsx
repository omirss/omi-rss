import { useEffect, useRef, useState } from "preact/hooks";
import type { JSX } from "preact";
import { useNavigate } from "@neutron-build/core/client";
import pkg from "../../package.json";
import { AppShell } from "../components/AppShell.js";
import { ErrorState, Skeleton } from "../components/states.js";
import { useToast } from "../components/Toast.js";
import { useSession } from "../lib/auth.js";
import { ApiError, discoveryApi, saveBlob, usersApi } from "../lib/client.js";
import type { OpmlImportResult, UserDetail } from "../lib/api-types.js";
import { Modal, Section } from "../components/secondary/widgets.js";
import {
  DownloadIcon,
  KeyIcon,
  PencilIcon,
  TrashIcon,
  UploadIcon,
} from "../components/secondary/icons.js";

export const config = { mode: "app" };

const GITHUB_URL = "https://github.com/omirss/omi-rss";

type MePhase = "loading" | "ready" | "error";

function initialsOf(user: UserDetail | null): string {
  if (!user) return "";
  const first = user.firstName?.[0] ?? user.username[0] ?? "";
  const last = user.lastName?.[0] ?? "";
  return (first + last).toUpperCase() || user.username.slice(0, 2).toUpperCase();
}

export default function SettingsPage() {
  const { showToast } = useToast();
  const { user, refreshUser, logout } = useSession();
  const navigate = useNavigate();
  const [phase, setPhase] = useState<MePhase>("loading");
  const [me, setMe] = useState<UserDetail | null>(null);
  const [profileUsername, setProfileUsername] = useState("");
  const [profileFirstName, setProfileFirstName] = useState("");
  const [profileLastName, setProfileLastName] = useState("");
  const [savingProfile, setSavingProfile] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [avatarVersion, setAvatarVersion] = useState(0);
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const importInputRef = useRef<HTMLInputElement>(null);
  const [importing, setImporting] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [changingPassword, setChangingPassword] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deletePassword, setDeletePassword] = useState("");
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [deletingAccount, setDeletingAccount] = useState(false);

  const load = async () => {
    setPhase("loading");
    try {
      const { user: detail } = await usersApi.getMe();
      setMe(detail);
      setProfileUsername(detail.username);
      setProfileFirstName(detail.firstName ?? "");
      setProfileLastName(detail.lastName ?? "");
      setPhase("ready");
    } catch {
      setPhase("error");
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const profileDirty =
    me !== null &&
    (profileUsername !== me.username ||
      profileFirstName !== (me.firstName ?? "") ||
      profileLastName !== (me.lastName ?? ""));

  const onSaveProfile = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (!profileDirty || savingProfile) return;
    setSavingProfile(true);
    try {
      await usersApi.updateProfile({
        username: profileUsername.trim(),
        firstName: profileFirstName.trim(),
        lastName: profileLastName.trim(),
      });
      await refreshUser();
      await load();
      showToast({ title: "Profile updated", kind: "success" });
    } catch (error) {
      showToast({
        title: "Could not update profile",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setSavingProfile(false);
    }
  };

  const onAvatarPicked = async (event: JSX.TargetedEvent<HTMLInputElement, Event>) => {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = "";
    if (!file || uploadingAvatar) return;
    setUploadingAvatar(true);
    try {
      await usersApi.uploadAvatar(file);
      await refreshUser();
      await load();
      setAvatarVersion((version) => version + 1);
      showToast({ title: "Avatar updated", kind: "success" });
    } catch (error) {
      showToast({
        title: "Avatar upload failed",
        message: error instanceof ApiError ? error.message : "Images up to 5 MB (jpeg, png, gif, webp) are allowed",
        kind: "error",
      });
    } finally {
      setUploadingAvatar(false);
    }
  };

  const onExportOpml = async () => {
    if (exporting) return;
    setExporting(true);
    try {
      const blob = await discoveryApi.exportOpml();
      saveBlob(blob, "omi-rss-feeds.opml");
      showToast({ title: "OPML exported", message: "omi-rss-feeds.opml downloaded", kind: "success" });
    } catch (error) {
      showToast({
        title: "Export failed",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setExporting(false);
    }
  };

  const onImportPicked = async (event: JSX.TargetedEvent<HTMLInputElement, Event>) => {
    const file = event.currentTarget.files?.[0];
    event.currentTarget.value = "";
    if (!file || importing) return;
    setImporting(true);
    try {
      const response = await discoveryApi.importOpml(file);
      if (!response.success) {
        showToast({ title: "Import failed", message: response.error ?? "Please try again", kind: "error" });
        return;
      }
      const result = response.data as OpmlImportResult | undefined;
      showToast({
        title: "OPML imported",
        message: result
          ? `${result.imported} feed${result.imported === 1 ? "" : "s"} imported${result.failed > 0 ? `, ${result.failed} failed` : ""}`
          : undefined,
        kind: result && result.failed > 0 ? "info" : "success",
      });
    } catch (error) {
      showToast({
        title: "Import failed",
        message: error instanceof ApiError ? error.message : "Please try again",
        kind: "error",
      });
    } finally {
      setImporting(false);
    }
  };

  const onChangePassword = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (changingPassword) return;
    setPasswordError(null);
    if (newPassword.length < 8) {
      setPasswordError("New password must be at least 8 characters");
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordError("New passwords do not match");
      return;
    }
    setChangingPassword(true);
    try {
      await usersApi.updatePassword({ currentPassword, newPassword });
      setPasswordOpen(false);
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      showToast({ title: "Password changed", message: "Please sign in again with your new password", kind: "success" });
      await logout();
      navigate("/login");
    } catch (error) {
      setPasswordError(error instanceof ApiError ? error.message : "Could not change password");
    } finally {
      setChangingPassword(false);
    }
  };

  const onDeleteAccount = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (deletingAccount) return;
    setDeleteError(null);
    setDeletingAccount(true);
    try {
      await usersApi.deleteAccount(deletePassword);
      showToast({ title: "Account deleted", message: "Your account and data have been removed", kind: "info" });
      await logout();
      navigate("/login");
    } catch (error) {
      setDeleteError(error instanceof ApiError ? error.message : "Could not delete account");
    } finally {
      setDeletingAccount(false);
    }
  };

  const avatarUrl = user?.avatarUrl
    ? `${user.avatarUrl}${user.avatarUrl.includes("?") ? "&" : "?"}v=${avatarVersion}`
    : null;

  return (
    <AppShell title="Settings">
      <div class="page">
        {phase === "loading" ? (
          <div class="glass-card sec-card">
            <Skeleton variant="circle" />
            <Skeleton width="40%" />
            <Skeleton width="80%" />
            <Skeleton width="60%" />
          </div>
        ) : null}

        {phase === "error" ? (
          <ErrorState title="Could not load settings" message="Your account details are unavailable right now." />
        ) : null}

        {phase === "ready" && me ? (
          <>
            <Section title="Account">
              <div class="glass-card sec-card">
                <div class="settings-row">
                  <div class="settings-row-head">
                    <div class="settings-row-body">
                      <div class="settings-row-title">Avatar</div>
                      <div class="settings-row-subtitle">Shown in the sidebar. PNG, JPEG, GIF, or WebP up to 5 MB.</div>
                    </div>
                    <span class="settings-row-actions">
                      <button
                        type="button"
                        class="btn btn-secondary btn-sm"
                        disabled={uploadingAvatar}
                        onClick={() => avatarInputRef.current?.click()}
                      >
                        {uploadingAvatar ? <span class="spinner" /> : <UploadIcon size={15} />}
                        Upload new avatar
                      </button>
                    </span>
                  </div>
                  <div class="settings-row-content">
                    {avatarUrl ? (
                      <img class="profile-avatar" src={avatarUrl} alt="Your avatar" />
                    ) : (
                      <span class="profile-avatar-fallback">{initialsOf(me)}</span>
                    )}
                  </div>
                  <input
                    ref={avatarInputRef}
                    type="file"
                    accept="image/png,image/jpeg,image/gif,image/webp"
                    style="display: none;"
                    onChange={onAvatarPicked}
                  />
                </div>

                <form class="settings-row" onSubmit={onSaveProfile}>
                  <div class="settings-row-head">
                    <span class="settings-row-icon">
                      <PencilIcon size={16} />
                    </span>
                    <div class="settings-row-body">
                      <div class="settings-row-title">Profile</div>
                      <div class="settings-row-subtitle">Your name as it appears across Omi RSS.</div>
                    </div>
                    <span class="settings-row-actions">
                      <button type="submit" class="btn btn-primary btn-sm" disabled={!profileDirty || savingProfile}>
                        {savingProfile ? <span class="spinner" /> : null}
                        Save changes
                      </button>
                    </span>
                  </div>
                  <div class="settings-row-content" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: var(--sp-md);">
                    <label class="field">
                      <span class="label">Username</span>
                      <input
                        class="input"
                        type="text"
                        value={profileUsername}
                        minLength={3}
                        maxLength={50}
                        onInput={(event) => setProfileUsername(event.currentTarget.value)}
                      />
                    </label>
                    <label class="field">
                      <span class="label">First name</span>
                      <input
                        class="input"
                        type="text"
                        value={profileFirstName}
                        onInput={(event) => setProfileFirstName(event.currentTarget.value)}
                      />
                    </label>
                    <label class="field">
                      <span class="label">Last name</span>
                      <input
                        class="input"
                        type="text"
                        value={profileLastName}
                        onInput={(event) => setProfileLastName(event.currentTarget.value)}
                      />
                    </label>
                    <label class="field">
                      <span class="label">Email</span>
                      <input class="input" type="email" value={me.email} disabled />
                      <span class="field-hint">Email cannot be changed.</span>
                    </label>
                  </div>
                </form>

                <div class="settings-row">
                  <div class="settings-row-head">
                    <span class="settings-row-icon">
                      <KeyIcon size={16} />
                    </span>
                    <div class="settings-row-body">
                      <div class="settings-row-title">Password</div>
                      <div class="settings-row-subtitle">Changing your password signs you out everywhere.</div>
                    </div>
                    <span class="settings-row-actions">
                      <button
                        type="button"
                        class="btn btn-secondary btn-sm"
                        onClick={() => {
                          setPasswordError(null);
                          setPasswordOpen(true);
                        }}
                      >
                        Change password
                      </button>
                    </span>
                  </div>
                </div>
              </div>
            </Section>

            <Section title="Data">
              <div class="glass-card sec-card">
                <div class="settings-row">
                  <div class="settings-row-head">
                    <span class="settings-row-icon">
                      <UploadIcon size={16} />
                    </span>
                    <div class="settings-row-body">
                      <div class="settings-row-title">OPML import</div>
                      <div class="settings-row-subtitle">Add feeds from another reader via an OPML file.</div>
                    </div>
                    <span class="settings-row-actions">
                      <button
                        type="button"
                        class="btn btn-secondary btn-sm"
                        disabled={importing}
                        onClick={() => importInputRef.current?.click()}
                      >
                        {importing ? <span class="spinner" /> : <UploadIcon size={15} />}
                        Import OPML
                      </button>
                    </span>
                  </div>
                  <input
                    ref={importInputRef}
                    type="file"
                    accept=".opml,.xml,text/xml,application/xml,text/x-opml"
                    style="display: none;"
                    onChange={onImportPicked}
                  />
                </div>

                <div class="settings-row">
                  <div class="settings-row-head">
                    <span class="settings-row-icon">
                      <DownloadIcon size={16} />
                    </span>
                    <div class="settings-row-body">
                      <div class="settings-row-title">OPML export</div>
                      <div class="settings-row-subtitle">Download all of your feed subscriptions as OPML.</div>
                    </div>
                    <span class="settings-row-actions">
                      <button
                        type="button"
                        class="btn btn-secondary btn-sm"
                        disabled={exporting}
                        onClick={() => void onExportOpml()}
                      >
                        {exporting ? <span class="spinner" /> : <DownloadIcon size={15} />}
                        Export OPML
                      </button>
                    </span>
                  </div>
                </div>
              </div>
            </Section>

            <Section title="Danger zone">
              <div class="glass-card sec-card danger-card">
                <div class="settings-row">
                  <div class="settings-row-head">
                    <span class="settings-row-icon">
                      <TrashIcon size={16} />
                    </span>
                    <div class="settings-row-body">
                      <div class="settings-row-title danger-title">Delete account</div>
                      <div class="settings-row-subtitle">
                        Permanently removes your account, feeds, folders, and reading history.
                      </div>
                    </div>
                    <span class="settings-row-actions">
                      <button
                        type="button"
                        class="btn btn-secondary btn-sm"
                        style="color: var(--c-error); border-color: var(--c-error);"
                        onClick={() => {
                          setDeletePassword("");
                          setDeleteError(null);
                          setDeleteOpen(true);
                        }}
                      >
                        Delete account
                      </button>
                    </span>
                  </div>
                </div>
              </div>
            </Section>

            <Section title="About">
              <div class="glass-card sec-card">
                <div>
                  <div class="about-row">
                    <span class="about-key">Version</span>
                    <span class="about-value">{pkg.version}</span>
                  </div>
                  <div class="about-row">
                    <span class="about-key">Source</span>
                    <a class="about-link" href={GITHUB_URL} target="_blank" rel="noreferrer noopener">
                      github.com/omirss/omi-rss
                    </a>
                  </div>
                </div>
              </div>
            </Section>
          </>
        ) : null}
      </div>

      {passwordOpen ? (
        <Modal
          title="Change password"
          onClose={() => {
            setPasswordOpen(false);
            setPasswordError(null);
          }}
        >
          <form onSubmit={onChangePassword}>
            <label class="field">
              <span class="label">Current password</span>
              <input
                class="input"
                type="password"
                value={currentPassword}
                autocomplete="current-password"
                onInput={(event) => setCurrentPassword(event.currentTarget.value)}
                autofocus
              />
            </label>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">New password</span>
              <input
                class="input"
                type="password"
                value={newPassword}
                autocomplete="new-password"
                minLength={8}
                onInput={(event) => setNewPassword(event.currentTarget.value)}
              />
              <span class="field-hint">At least 8 characters</span>
            </label>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">Confirm new password</span>
              <input
                class="input"
                type="password"
                value={confirmPassword}
                autocomplete="new-password"
                minLength={8}
                onInput={(event) => setConfirmPassword(event.currentTarget.value)}
              />
            </label>
            {passwordError ? (
              <p class="field-error" style="margin-top: var(--sp-md);" role="alert">
                {passwordError}
              </p>
            ) : null}
            <div class="modal-actions">
              <button
                type="button"
                class="btn btn-ghost"
                onClick={() => {
                  setPasswordOpen(false);
                  setPasswordError(null);
                }}
              >
                Cancel
              </button>
              <button type="submit" class="btn btn-primary" disabled={changingPassword || !currentPassword || !newPassword}>
                {changingPassword ? <span class="spinner" /> : null}
                Update password
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {deleteOpen ? (
        <Modal
          title="Delete account"
          onClose={() => {
            setDeleteOpen(false);
            setDeleteError(null);
          }}
        >
          <form onSubmit={onDeleteAccount}>
            <p class="page-subtitle">
              This permanently deletes your account, feeds, folders, and reading history. There is no undo.
            </p>
            <label class="field" style="margin-top: var(--sp-md);">
              <span class="label">Confirm with your password</span>
              <input
                class="input"
                type="password"
                value={deletePassword}
                autocomplete="current-password"
                onInput={(event) => setDeletePassword(event.currentTarget.value)}
                autofocus
              />
            </label>
            {deleteError ? (
              <p class="field-error" style="margin-top: var(--sp-md);" role="alert">
                {deleteError}
              </p>
            ) : null}
            <div class="modal-actions">
              <button
                type="button"
                class="btn btn-ghost"
                onClick={() => {
                  setDeleteOpen(false);
                  setDeleteError(null);
                }}
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn btn-primary"
                style="background: var(--c-error);"
                disabled={deletingAccount || !deletePassword}
              >
                {deletingAccount ? <span class="spinner" /> : null}
                Delete forever
              </button>
            </div>
          </form>
        </Modal>
      ) : null}
    </AppShell>
  );
}
