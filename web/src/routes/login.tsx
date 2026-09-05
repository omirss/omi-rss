import { useEffect, useState } from "preact/hooks";
import type { JSX } from "preact";
import { route, useNavigate } from "@neutron-build/core/client";
import { useSession } from "../lib/auth.js";
import { ApiError } from "../lib/client.js";
import { AlertIcon, EyeIcon, EyeOffIcon } from "../components/Icons.js";

export const config = { mode: "app" };

type AuthTab = "login" | "register";

export default function LoginPage() {
  const { status, login, register } = useSession();
  const navigate = useNavigate();
  const [tab, setTab] = useState<AuthTab>("login");
  const [emailOrUsername, setEmailOrUsername] = useState("");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (status === "authenticated") {
      navigate(route("/"));
    }
  }, [status, navigate]);

  const onSubmit = async (event: JSX.TargetedEvent<HTMLFormElement, Event>) => {
    event.preventDefault();
    if (submitting) return;
    setError(null);

    if (tab === "register") {
      if (username.trim().length < 3) {
        setError("Username must be at least 3 characters");
        return;
      }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
        setError("Enter a valid email address");
        return;
      }
      if (password.length < 8) {
        setError("Password must be at least 8 characters");
        return;
      }
      if (password !== confirmPassword) {
        setError("Passwords do not match");
        return;
      }
    } else if (!emailOrUsername.trim() || !password) {
      setError("Enter your credentials to continue");
      return;
    }

    setSubmitting(true);
    try {
      if (tab === "register") {
        await register({ email: email.trim(), username: username.trim(), password });
      } else {
        await login(emailOrUsername.trim(), password);
      }
      navigate(route("/"));
    } catch (caught) {
      if (caught instanceof ApiError) {
        setError(caught.message);
      } else if (caught instanceof Error) {
        setError(caught.message);
      } else {
        setError("Unable to connect. Try again.");
      }
      setSubmitting(false);
    }
  };

  return (
    <div class="auth-screen">
      <div class="glass-panel auth-card">
        <div class="auth-brand">
          <h1 class="auth-title">Omi RSS</h1>
          <p class="auth-subtitle">
            {tab === "login" ? "Sign in to your reading library" : "Create your reading account"}
          </p>
        </div>

        <div class="segmented" style="align-self: center;">
          <button
            type="button"
            class={`segmented-item${tab === "login" ? " segmented-item-active" : ""}`}
            onClick={() => {
              setTab("login");
              setError(null);
            }}
          >
            Sign in
          </button>
          <button
            type="button"
            class={`segmented-item${tab === "register" ? " segmented-item-active" : ""}`}
            onClick={() => {
              setTab("register");
              setError(null);
            }}
          >
            Create account
          </button>
        </div>

        <form class="auth-form" onSubmit={onSubmit}>
          <div class="auth-form-fields">
            {tab === "login" ? (
              <label class="field">
                <span class="label">Email or username</span>
                <input
                  class="input"
                  type="text"
                  value={emailOrUsername}
                  onInput={(event) => setEmailOrUsername(event.currentTarget.value)}
                  autocomplete="username"
                  autofocus={tab === "login"}
                />
              </label>
            ) : (
              <>
                <label class="field">
                  <span class="label">Email</span>
                  <input
                    class="input"
                    type="email"
                    value={email}
                    onInput={(event) => setEmail(event.currentTarget.value)}
                    autocomplete="email"
                  />
                </label>
                <label class="field">
                  <span class="label">Username</span>
                  <input
                    class="input"
                    type="text"
                    value={username}
                    onInput={(event) => setUsername(event.currentTarget.value)}
                    autocomplete="username"
                    minLength={3}
                    maxLength={50}
                  />
                </label>
              </>
            )}
            <label class="field">
              <span class="label">Password</span>
              <div class="input-wrap">
                <input
                  class="input"
                  type={passwordVisible ? "text" : "password"}
                  value={password}
                  onInput={(event) => setPassword(event.currentTarget.value)}
                  autocomplete={tab === "login" ? "current-password" : "new-password"}
                  minLength={tab === "register" ? 8 : undefined}
                  style="padding-right: 44px;"
                />
                <button
                  type="button"
                  class="btn btn-ghost btn-icon btn-sm input-trailing"
                  onClick={() => setPasswordVisible((visible) => !visible)}
                  aria-label={passwordVisible ? "Hide password" : "Show password"}
                >
                  {passwordVisible ? <EyeOffIcon size={16} /> : <EyeIcon size={16} />}
                </button>
              </div>
              {tab === "register" ? <span class="field-hint">At least 8 characters</span> : null}
            </label>
            {tab === "register" ? (
              <label class="field">
                <span class="label">Confirm password</span>
                <div class="input-wrap">
                  <input
                    class="input"
                    type={passwordVisible ? "text" : "password"}
                    value={confirmPassword}
                    onInput={(event) => setConfirmPassword(event.currentTarget.value)}
                    autocomplete="new-password"
                    minLength={8}
                    style="padding-right: 44px;"
                  />
                </div>
                {confirmPassword && password !== confirmPassword ? (
                  <span class="field-hint" style="color: var(--c-error);">
                    Passwords do not match
                  </span>
                ) : null}
              </label>
            ) : null}
          </div>

          {error ? (
            <div class="auth-error" role="alert">
              <AlertIcon size={16} />
              <span>{error}</span>
            </div>
          ) : null}

          <button type="submit" class="btn btn-primary auth-submit" disabled={submitting || status === "loading"}>
            {submitting ? <span class="spinner" /> : null}
            {submitting ? "Please wait" : tab === "login" ? "Sign in" : "Create account"}
          </button>
        </form>

        <div class="auth-footer">
          {tab === "login" ? "New to Omi RSS? " : "Already have an account? "}
          <button
            type="button"
            class="auth-switch"
            onClick={() => {
              setTab(tab === "login" ? "register" : "login");
              setError(null);
            }}
          >
            {tab === "login" ? "Create an account" : "Sign in"}
          </button>
        </div>
      </div>
    </div>
  );
}
