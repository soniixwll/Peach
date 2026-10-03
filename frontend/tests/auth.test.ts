import { afterEach, describe, expect, it, vi } from "vitest";

describe("Cognito configuration", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it("uses the public Cognito settings and builds the hosted logout URL", async () => {
    vi.stubEnv("NEXT_PUBLIC_COGNITO_REGION", "us-east-1");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_USER_POOL_ID", "us-east-1_example");
    vi.stubEnv("NEXT_PUBLIC_COGNITO_CLIENT_ID", "public-client-id");
    vi.stubEnv(
      "NEXT_PUBLIC_COGNITO_DOMAIN",
      "https://example.auth.us-east-1.amazoncognito.com",
    );
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://www.example.com");

    const { authIsConfigured, cognitoLogoutUrl, loginUrl, oidcSettings } =
      await import("@/lib/auth");

    expect(authIsConfigured).toBe(true);
    expect(oidcSettings.authority).toBe(
      "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_example",
    );
    expect(oidcSettings.client_id).toBe("public-client-id");
    expect(oidcSettings.response_type).toBe("code");
    expect(oidcSettings.scope).toBe("openid email profile");
    expect(loginUrl).toBe("https://www.example.com/login/");

    const logoutUrl = new URL(cognitoLogoutUrl());
    expect(logoutUrl.origin).toBe(
      "https://example.auth.us-east-1.amazoncognito.com",
    );
    expect(logoutUrl.pathname).toBe("/logout");
    expect(logoutUrl.searchParams.get("client_id")).toBe("public-client-id");
    expect(logoutUrl.searchParams.get("logout_uri")).toBe(
      "https://www.example.com/login/",
    );
  });
});
