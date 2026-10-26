"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import {
  ArrowRight,
  LoaderCircle,
  LockKeyhole,
  CheckCheck,
} from "lucide-react";
import { authClient } from "@/lib/auth-client";
import type { Profile } from "@/lib/workout";
export default function PasswordForm({ reset = false }: { reset?: boolean }) {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null),
    [token, setToken] = useState(""),
    [ready, setReady] = useState(false),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [done, setDone] = useState(false);
  useEffect(() => {
    let active = true;
    if (reset) {
      const value = new URL(location.href).searchParams.get("token");
      Promise.resolve().then(() => {
        if (!active) return;
        if (value) {
          setToken(value);
          setReady(true);
        } else
          setError(
            "This reset link is invalid or expired. Request a new link.",
          );
      });
    } else {
      void fetch("/api/account", { cache: "no-store" })
        .then(async (response) => {
          if (!response.ok) throw Error();
          return response.json();
        })
        .then((account) => {
          if (!active) return;
          if (!account.needsPassword) {
            router.replace(`/#${account.profile}/today`);
            return;
          }
          setProfile(account.profile);
          setReady(true);
        })
        .catch(() => {
          if (active)
            setError("Your setup session expired. Request a fresh email link.");
        });
    }
    return () => {
      active = false;
    };
  }, [reset, router]);
  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (busy) return;
    const form = new FormData(event.currentTarget),
      password = String(form.get("password"));
    if (password !== String(form.get("confirm"))) {
      setError("The passwords don’t match. Please try again.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      if (reset) {
        const result = await authClient.resetPassword({
          newPassword: password,
          token,
        });
        if (result.error) {
          setError(
            "This reset link is invalid, expired or already used. Request a new link.",
          );
          return;
        }
        setToken("");
        setDone(true);
        history.replaceState(null, "", "/reset-password");
      } else {
        const response = await fetch("/api/account/password", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ newPassword: password }),
        });
        if (!response.ok) {
          setError(
            "Your setup session expired or a password is already set. Use Forgot password if needed.",
          );
          return;
        }
        router.replace(`/#${profile}/today`);
      }
    } catch {
      setError("Could not connect. Please try again.");
    } finally {
      setBusy(false);
    }
  };
  return (
    <main className="auth-page">
      <section className="auth-card">
        <span className="auth-avatar">
          {done ? <CheckCheck size={26} /> : <LockKeyhole size={24} />}
        </span>
        <div className="eyebrow">TOGETHER STRONG · PRIVATE ACCESS</div>
        <h1>
          {done
            ? "A fresh start, saved."
            : reset
              ? "Choose a new password."
              : `Make it yours${profile ? `, ${profile}` : ""}.`}
        </h1>
        <p>
          {done
            ? "Your password is updated. Existing sessions have been signed out. Sign in again with your new password."
            : "Choose at least 12 characters. Keep your password private and save it in a password manager."}
        </p>
        {error && (
          <p className="error-text" role="alert">
            {error}
          </p>
        )}
        {ready && !done && (
          <form onSubmit={submit}>
            <label>
              {reset ? "New password" : "Choose password"}
              <input
                name="password"
                type="password"
                required
                minLength={12}
                maxLength={128}
                autoComplete="new-password"
              />
            </label>
            <label>
              Confirm password
              <input
                name="confirm"
                type="password"
                required
                minLength={12}
                maxLength={128}
                autoComplete="new-password"
              />
            </label>
            <button className="dark-button" disabled={busy}>
              {busy ? (
                <LoaderCircle size={17} className="spin" />
              ) : reset ? (
                "Reset my password"
              ) : (
                "Save password & start"
              )}
              <ArrowRight size={17} />
            </button>
          </form>
        )}
        <Link className="text-button" href="/">
          {done ? "Back to sign in" : "Back to profile choices"}
        </Link>
      </section>
    </main>
  );
}
