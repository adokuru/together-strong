"use client";
import { useState } from "react";
import { ArrowRight, LoaderCircle, LockKeyhole, Mail } from "lucide-react";
import { authClient } from "@/lib/auth-client";
import type { Profile } from "@/lib/workout";
export default function AuthGate({
  profile,
  configured,
  emailEnabled,
  allowDemo,
  onDemo,
  onLogin,
}: {
  profile: Profile;
  configured: boolean;
  emailEnabled: boolean;
  allowDemo: boolean;
  onDemo: () => void;
  onLogin: () => Promise<void>;
}) {
  const [mode, setMode] = useState<"login" | "setup" | "reset">("login"),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [sent, setSent] = useState(false);
  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    const form = new FormData(event.currentTarget),
      email = String(form.get("email")).trim();
    try {
      const result =
        mode === "setup"
          ? await authClient.signIn.magicLink({
              email,
              name: profile,
              callbackURL: "/set-password",
              newUserCallbackURL: "/set-password",
              errorCallbackURL: `/#${profile}/today`,
            })
          : mode === "reset"
            ? await authClient.requestPasswordReset({
                email,
                redirectTo: `${location.origin}/reset-password`,
              })
            : await authClient.signIn.email({
                email,
                password: String(form.get("password")),
              });
      if (result.error) {
        setError(
          mode === "login"
            ? "Could not sign in. Check your details, or request a private setup or reset link."
            : "The email could not be sent. Please try again later.",
        );
        return;
      }
      if (mode === "login") await onLogin();
      else setSent(true);
    } catch {
      setError("Could not connect. Please try again.");
    } finally {
      setBusy(false);
    }
  };
  const change = (next: typeof mode) => {
    setMode(next);
    setSent(false);
    setError("");
  };
  return (
    <section className="auth-card">
      <span className="auth-avatar">{profile[0]}</span>
      <div className="eyebrow">YOUR OWN LITTLE CORNER</div>
      <h1>
        {mode === "reset"
          ? "A fresh start."
          : mode === "setup"
            ? `Let’s get you set up, ${profile}.`
            : `Welcome back, ${profile}.`}
      </h1>
      <p>
        {!configured
          ? "Your secure training space is being configured."
          : mode === "reset"
            ? "We’ll email a private link to choose a new password. You never need to share your password with anyone."
            : mode === "setup"
              ? "Verify your email first. Then choose your own password for your private workout space."
              : "A private sign-in keeps your progress yours, on every device."}
      </p>
      {configured &&
        (sent ? (
          <div className="email-sent" role="status">
            <Mail size={26} />
            <h2>Check your inbox.</h2>
            <p>
              If this is an invited address
              {mode === "reset" ? " with an account" : ""}, a private link will
              arrive shortly. Check spam, too. Links expire in 15 minutes and
              work once.
            </p>
            <button className="text-button" onClick={() => change("login")}>
              Back to sign in <ArrowRight size={16} />
            </button>
          </div>
        ) : (
          <>
            <form onSubmit={submit}>
              <label>
                Email address
                <input
                  name="email"
                  type="email"
                  autoComplete="email"
                  required
                  placeholder="Your invited email"
                />
              </label>
              {mode === "login" && (
                <label>
                  Password
                  <input
                    name="password"
                    type="password"
                    minLength={12}
                    maxLength={128}
                    autoComplete="current-password"
                    required
                    placeholder="At least 12 characters"
                  />
                </label>
              )}
              {error && (
                <p className="error-text" role="alert">
                  {error}
                </p>
              )}
              <button
                className="dark-button"
                disabled={busy || (mode !== "login" && !emailEnabled)}
              >
                {busy ? (
                  <LoaderCircle size={18} className="spin" />
                ) : mode === "setup" ? (
                  "Email my setup link"
                ) : mode === "reset" ? (
                  "Send password reset link"
                ) : (
                  "Sign in & get stronger"
                )}
                <ArrowRight size={17} />
              </button>
            </form>
            {mode === "login" ? (
              <>
                <button
                  className="text-button auth-toggle"
                  onClick={() => change("setup")}
                >
                  First time? Email me a setup link
                </button>
                <button
                  className="text-button forgot-link"
                  onClick={() => change("reset")}
                >
                  Forgot password?
                </button>
              </>
            ) : (
              <button
                className="text-button auth-toggle"
                onClick={() => change("login")}
              >
                Back to sign in
              </button>
            )}
            {!emailEnabled && (
              <p className="email-pending">
                Private email delivery is being connected. No email has been
                sent.
              </p>
            )}
          </>
        ))}
      {allowDemo && (
        <div className="demo-option">
          <button className="text-button" onClick={onDemo}>
            Try on this device <ArrowRight size={16} />
          </button>
          <small>Local preview only. This browser stores your logs.</small>
        </div>
      )}
      <div className="auth-lock">
        <LockKeyhole size={14} /> Only invited, verified accounts can access
        workouts.
      </div>
    </section>
  );
}
