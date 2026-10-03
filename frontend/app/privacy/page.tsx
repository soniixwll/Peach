import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export const metadata = { title: "Privacy Policy | Peach" };

export default function PrivacyPolicyPage() {
  return (
    <div className="grid gap-8">
      <PageHeader
        icon="🔒"
        title="Privacy Policy"
        description="How Peach uses information for this university lab project."
      />

      <Card>
        <CardHeader>
          <CardTitle>Privacy at Peach</CardTitle>
        </CardHeader>
        <CardContent className="grid max-w-prose gap-4 text-sm leading-6 text-muted-foreground">
          <p>
            Peach is a university lab project. It uses authentication
            information, such as your email address and name, to sign you in and
            identify your account in the application.
          </p>
          <p>
            Google sign-in is used only for authentication. Peach does not use
            Google sign-in to access your Gmail, Google Drive, contacts, or
            other Google services.
          </p>
          <p>
            Peach also stores information you choose to enter in the
            application, such as tasks. Do not enter sensitive personal
            information into this lab application.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
