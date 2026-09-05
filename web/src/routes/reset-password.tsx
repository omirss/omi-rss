import { useEffect, useState } from "preact/hooks";
import type { JSX } from "preact";
import { route, useNavigate, useSearchParams } from "@neutron-build/core/client";
import { authApi, ApiError } from "../lib/client.js";
import { useToast } from "../components/Toast.js";
import { AlertIcon, EyeIcon, EyeOffIcon, RssIcon } from "../components/Icons.js";

export const config = { mode: "app" };

type Phase = "form" | "done" | "error";

export default function ResetPasswordPage() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { showToast } = useToast();
  const token = searchParams.get("token") ?? "";
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [phase, setPhase] = useState<Phase>(token ? "form" : "error");
  const [error, setError] = useState<string | null>(token ? null : "This link is missing its reset token. Request a new password reset email.");

  useEffect(() => {
    if (phase === "done") {
      navigate(route("/login"));
    }
  }, [phase, navigate]);

  const onSubmit = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (submitting) return;
    setError(null);
    if (password.length < 8) {
      setError("New password must be at least 8 characters");
      return;
    }
    if (password !== confirm) {
      setError("Passwords do not match");
      return;
    }
    setSubmitting(true);
    try {
      await authApi.resetPassword(token, password);
      showToast({ title: "Password reset", message: "Sign in with your new password", kind: "success" });
      setPhase("done");
    } catch (caught) {
      setError(
        caught instanceof ApiError
          ? caught.message
          : caught instanceof Error
            ? caught.message
            : "Could not reset password. The link may have expired.",
      );
      setPhase("error");
    } finally {
      setSubmitting(false);
    }
  };

  const canEdit = phase !== "done" && !submitting;

  return (
    <div class="auth-screen">
      <div class="glass-panel auth-card">
        <div class="auth-brand">
          <span class="auth-logo">
            <RssIcon size={26} />
          </span>
          <h1 class="auth-title">Reset password</h1>
          <p class="auth-subtitle">Choose a new password for your account.</p>
        </div>

        <form class="auth-form" onSubmit={onSubmit}>
          <div class="auth-form-fields">
            <label class="field">
              <span class="label">New password</span>
              <div class="input-wrap">
                <input
                  class="input"
                  type={passwordVisible ? "text" : "password"}
                  value={password}
                  onInput={(event) => setPassword(event.currentTarget.value)}
                  autocomplete="new-password"
                  minLength={8}
                  disabled={!canEdit}
                  style="padding-right: 44px;"
                />
                <button
                  type="button"
                  class="btn btn-ghost btn-icon btn-sm input-trailing"
                  onClick={() => setPasswordVisible((visible) => !visible)}
                  aria-label={passwordVisible ? "Hide password" : "Show password"}
                  tabIndex={canEdit ? undefined : -1}
                >
                  {passwordVisible ? <EyeOffIcon size={16} /> : <EyeIcon size={16} />}
                </button>
              </div>
              <span class="field-hint">At least 8 characters</span>
            </label>
            <label class="field">
              <span class="label">Confirm new password</span>
              <input
                class="input"
                type={passwordVisible ? "text" : "password"}
                value={confirm}
                onInput={(event) => setConfirm(event.currentTarget.value)}
                autocomplete="new-password"
                minLength={8}
                disabled={!canEdit}
              />
            </label>
          </div>

          {error ? (
            <div class="auth-error" role="alert">
              <AlertIcon size={16} />
              <span>{error}</span>
            </div>
          ) : null}

          <button type="submit" class="btn btn-primary auth-submit" disabled={!canEdit || !password || !confirm}>
            {submitting ? <span class="spinner" /> : null}
            {submitting ? "Please wait" : "Reset password"}
          </button>
        </form>

        <div class="auth-footer">
          <a class="auth-switch" href="/login">Back to sign in</a>
        </div>
      </div>
    </div>
  );
}
