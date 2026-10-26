import Tracker from "./tracker";
export default function Page() {
  const configured = Boolean(
    process.env.DATABASE_URL &&
    process.env.BETTER_AUTH_SECRET &&
    process.env.DAVID_EMAIL &&
    process.env.MARY_EMAIL &&
    process.env.DAVID_INVITE_CODE &&
    process.env.MARY_INVITE_CODE,
  );
  return (
    <Tracker cloudConfigured={configured} allowDemo={!process.env.VERCEL} />
  );
}
