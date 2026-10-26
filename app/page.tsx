import Tracker from "./tracker";
import { emailConfigured } from "@/lib/mail";
export const dynamic = "force-dynamic";
export default function Page() {
  const configured = Boolean(
    process.env.DATABASE_URL &&
    process.env.BETTER_AUTH_SECRET &&
    process.env.DAVID_EMAIL &&
    process.env.MARY_EMAIL,
  );
  return (
    <Tracker
      cloudConfigured={configured}
      emailConfigured={emailConfigured()}
      allowDemo={!process.env.VERCEL}
    />
  );
}
