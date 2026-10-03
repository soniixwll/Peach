import type { AuthProviderProps } from "react-oidc-context";

const region = process.env.NEXT_PUBLIC_COGNITO_REGION ?? "us-east-1";
const userPoolId = process.env.NEXT_PUBLIC_COGNITO_USER_POOL_ID ?? "missing";
const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? "missing";
const cognitoDomain = (
  process.env.NEXT_PUBLIC_COGNITO_DOMAIN ??
  "https://missing.auth.us-east-1.amazoncognito.com"
).replace(/\/$/, "");
const appUrl = (
  process.env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3000"
).replace(/\/$/, "");

export const authIsConfigured =
  userPoolId !== "missing" &&
  clientId !== "missing" &&
  !cognitoDomain.includes("//missing.");

export const loginUrl = `${appUrl}/login/`;

export const oidcConfig = {
  authority: `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`,
  client_id: clientId,
  redirect_uri: loginUrl,
  response_type: "code",
  scope: "openid email profile",
  onSigninCallback: () => {
    window.location.replace("/");
  },
} satisfies AuthProviderProps;

export function cognitoLogoutUrl() {
  const query = new URLSearchParams({
    client_id: clientId,
    logout_uri: loginUrl,
  });

  return `${cognitoDomain}/logout?${query.toString()}`;
}
