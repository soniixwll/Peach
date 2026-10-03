"use client";

import Link from "next/link";
import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { authIsConfigured } from "@/lib/auth";

export default function LoginPage() {
  const auth = useAuth();

  if (!authIsConfigured) {
    return (
      <Card className="mx-auto max-w-lg">
        <CardHeader>
          <CardTitle>Authentication is not configured</CardTitle>
          <CardDescription>
            Add the public Cognito settings before building Peach.
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  if (auth.isLoading || auth.activeNavigator) {
    return (
      <Card className="mx-auto max-w-lg">
        <CardHeader>
          <CardTitle>Signing you in</CardTitle>
          <CardDescription>
            Completing the secure sign-in with Amazon Cognito…
          </CardDescription>
        </CardHeader>
      </Card>
    );
  }

  if (auth.error) {
    return (
      <Card className="mx-auto max-w-lg">
        <CardHeader>
          <CardTitle>Sign-in did not complete</CardTitle>
          <CardDescription>{auth.error.message}</CardDescription>
        </CardHeader>
        <CardContent>
          <Button type="button" onClick={() => void auth.signinRedirect()}>
            Try again
          </Button>
        </CardContent>
      </Card>
    );
  }

  if (auth.isAuthenticated) {
    return (
      <Card className="mx-auto max-w-lg">
        <CardHeader>
          <CardTitle>You are signed in</CardTitle>
          <CardDescription>
            Signed in as {auth.user?.profile.email}
          </CardDescription>
        </CardHeader>
        <CardFooter>
          <Button asChild>
            <Link href="/">Continue to Peach</Link>
          </Button>
        </CardFooter>
      </Card>
    );
  }

  return (
    <Card className="mx-auto max-w-lg">
      <CardHeader>
        <CardTitle>Sign in to Peach</CardTitle>
        <CardDescription>
          Continue to Cognito Managed Login to sign in or create an account with
          email and password, or continue with Google.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <Button type="button" onClick={() => void auth.signinRedirect()}>
          Sign in or create account
        </Button>
      </CardContent>
    </Card>
  );
}
