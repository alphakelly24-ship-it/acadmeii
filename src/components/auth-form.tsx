"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

type AuthMode = "signin" | "signup";

type AuthFormProps = {
  mode: AuthMode;
};

function getAuthErrorMessage(error: unknown, mode: AuthMode) {
  const message = error instanceof Error ? error.message : "";
  const normalized = message.toLowerCase();

  if (message.includes("NEXT_PUBLIC_SUPABASE_URL")) {
    return "Authentication is not configured yet. Add your Supabase URL and anon key to .env.local, then restart the app.";
  }

  if (normalized.includes("invalid login credentials")) {
    return "That email and password combination was not recognized. Check them and try again.";
  }

  if (normalized.includes("email not confirmed") || normalized.includes("email not verified")) {
    return "Confirm your email using the link from Supabase before signing in.";
  }

  if (
    normalized.includes("user already registered") ||
    normalized.includes("already been registered") ||
    normalized.includes("already registered")
  ) {
    return "An account may already exist for this email. Try signing in instead.";
  }

  if (normalized.includes("password") && (normalized.includes("short") || normalized.includes("minimum"))) {
    return message;
  }

  if (normalized.includes("failed to fetch") || normalized.includes("network")) {
    return "We could not reach the authentication service. Check your connection and try again.";
  }

  return mode === "signin"
    ? "We could not sign you in. Check your details and try again."
    : "We could not create your account. Check your details and try again.";
}

export function AuthForm({ mode }: AuthFormProps) {
  const router = useRouter();
  const isSignup = mode === "signup";
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const [statusMessage, setStatusMessage] = useState("");
  const supabaseConfigured = Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  );

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErrorMessage("");
    setStatusMessage("");
    setIsSubmitting(true);

    const values = new FormData(event.currentTarget);
    const email = String(values.get("email") ?? "").trim();
    const password = String(values.get("password") ?? "");

    try {
      const supabase = createClient();

      if (isSignup) {
        const displayName = String(values.get("displayName") ?? "").trim();
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { display_name: displayName },
          },
        });

        if (error) {
          throw error;
        }

        if (data.session) {
          setStatusMessage("Your account is ready. Taking you to the course catalog…");
          router.replace("/courses");
          router.refresh();
          return;
        }

        setStatusMessage(
          "If email confirmation is enabled, check your inbox for a confirmation link. Already registered? Sign in instead.",
        );
        return;
      }

      const { data, error } = await supabase.auth.signInWithPassword({ email, password });

      if (error) {
        throw error;
      }

      if (!data.session) {
        setStatusMessage(
          "We could not establish an active session. Complete any required verification, then try again.",
        );
        return;
      }

      setStatusMessage("You are signed in. Taking you to the course catalog…");
      router.replace("/courses");
      router.refresh();
    } catch (error) {
      setErrorMessage(getAuthErrorMessage(error, mode));
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <section className="auth-card" aria-labelledby="auth-heading">
      <p className="eyebrow auth-eyebrow">Academi account</p>
      <h1 className="auth-heading" id="auth-heading">
        {isSignup ? "Create your account" : "Sign in to keep learning"}
      </h1>
      <p className="auth-intro">
        {isSignup
          ? "Save your place and build a steady learning practice, one lesson at a time."
          : "Pick up your learning journey and return to the courses that matter to you."}
      </p>

      {!supabaseConfigured && (
        <p className="auth-config-note">
          Supabase is not configured in this environment. Add the project URL and anon key to
          <code> .env.local</code> to enable account actions.
        </p>
      )}

      <form className="auth-form" onSubmit={handleSubmit} aria-busy={isSubmitting}>
        {isSignup && (
          <div className="auth-field">
            <label htmlFor="displayName">Name</label>
            <input
              autoComplete="name"
              className="auth-input"
              id="displayName"
              name="displayName"
              placeholder="Your name"
              required
            />
          </div>
        )}

        <div className="auth-field">
          <label htmlFor="email">Email address</label>
          <input
            autoComplete="email"
            className="auth-input"
            id="email"
            name="email"
            placeholder="you@example.com"
            required
            type="email"
          />
        </div>

        <div className="auth-field">
          <label htmlFor="password">Password</label>
          <input
            autoComplete={isSignup ? "new-password" : "current-password"}
            className="auth-input"
            id="password"
            name="password"
            required
            type="password"
          />
        </div>

        {errorMessage && (
          <p className="auth-feedback auth-error" role="alert">
            {errorMessage}
          </p>
        )}
        {statusMessage && (
          <p className="auth-feedback auth-success" role="status">
            {statusMessage}
          </p>
        )}

        <button className="button-solid auth-submit" disabled={isSubmitting} type="submit">
          {isSubmitting
            ? isSignup
              ? "Creating account…"
              : "Signing in…"
            : isSignup
              ? "Create account"
              : "Sign in"}
        </button>
      </form>

      <p className="auth-switch">
        {isSignup ? "Already have an account?" : "New to Academi?"}{" "}
        <Link className="text-link" href={isSignup ? "/auth/signin" : "/auth/signup"}>
          {isSignup ? "Sign in" : "Create an account"}
        </Link>
      </p>
    </section>
  );
}
