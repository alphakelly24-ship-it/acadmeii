import type { Metadata } from "next";
import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = {
  title: "Create account",
  description: "Create an Academi account and begin building practical skills.",
};

export default function SignUpPage() {
  return (
    <main className="auth-page" id="main-content">
      <AuthForm mode="signup" />
    </main>
  );
}
