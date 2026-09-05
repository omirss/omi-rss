import { useEffect, useRef, useState } from "preact/hooks";
import { useSearchParams } from "@neutron-build/core/client";
import { authApi, ApiError } from "../lib/client.js";
import { AlertIcon, CheckCircleIcon, RssIcon } from "../components/Icons.js";

export const config = { mode: "app" };

type Phase = "verifying" | "success" | "error";

export default function VerifyEmailPage() {
  const [searchParams] = useSearchParams();
  const token = searchParams.get("token") ?? "";
  const [phase, setPhase] = useState<Phase>(token ? "verifying" : "error");
  const [message, setMessage] = useState<string>(
    token ? "" : "This link is missing its verification token. Request a new email or sign in.",
  );
  const attemptedRef = useRef(false);

  useEffect(() => {
    if (!token || attemptedRef.current) return;
    attemptedRef.current = true;
    authApi
      .verifyEmail(token)
      .then(() => {
        setPhase("success");
        setMessage("");
      })
      .catch((error: unknown) => {
        setPhase("error");
        setMessage(
          error instanceof ApiError
            ? error.message
            : error instanceof Error
              ? error.message
              : "Email verification failed. The link may have expired.",
        );
      });
  }, [token]);

  return (
    <div class="auth-screen">
      <div class="glass-panel auth-card">
        <div class="auth-brand">
          <span class="auth-logo">
            <RssIcon size={26} />
          </span>
          <h1 class="auth-title">Email verification</h1>
          {phase === "verifying" ? <p class="auth-subtitle">Checking your verification link...</p> : null}
          {phase === "success" ? <p class="auth-subtitle">Your email address has been verified.</p> : null}
          {phase === "error" ? <p class="auth-subtitle">We could not verify this email address.</p> : null}
        </div>

        {phase === "verifying" ? (
          <div class="loading-block">
            <span class="spinner" />
            Verifying
          </div>
        ) : null}

        {phase === "success" ? (
          <>
            <div class="auth-error auth-success" role="status">
              <CheckCircleIcon size={16} />
              <span>Email verified successfully. You can close this page and sign in.</span>
            </div>
            <a class="btn btn-primary auth-submit" href="/login">
              Continue to sign in
            </a>
          </>
        ) : null}

        {phase === "error" ? (
          <>
            <div class="auth-error" role="alert">
              <AlertIcon size={16} />
              <span>{message}</span>
            </div>
            <a class="btn btn-primary auth-submit" href="/login">
              Back to sign in
            </a>
          </>
        ) : null}
      </div>
    </div>
  );
}
