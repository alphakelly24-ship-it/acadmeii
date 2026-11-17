import type { Metadata } from "next";
import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = {
  title: "Sign in",
  description: "Sign in to continue learning with Academi.",
};

export default function SignInPage() {
  return (
    <main className="auth-page" id="main-content">
      <AuthForm mode="signin" />
    </main>
  );
}
