import { execFileSync } from "node:child_process";
const files = execFileSync("git", ["ls-files", "--cached", "-z"], {
  encoding: "utf8",
})
  .split("\0")
  .filter(Boolean);
const forbidden =
  /(^|\/)(\.env(?!\.example$)[^/]*|\.vercel|\.private|\.agents|test-results|playwright-report|node_modules|\.next)(\/|$)|\.(pem|key|p12)$/;
const patterns = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  /postgres(?:ql)?:\/\/[^\s"']+:[^\s"']+@/i,
  /\b(?:ghp_|github_pat_|sk_live_|sk_test_|AKIA)[A-Za-z0-9_]{16,}/,
  /\b(?:DATABASE_URL|BETTER_AUTH_SECRET|DAVID_INVITE_CODE|MARY_INVITE_CODE)[ \t]*=[ \t]*["']?[^\s"'\n]+/,
];
const problems = [];
for (const file of files) {
  if (forbidden.test(file)) {
    problems.push(`${file}: forbidden public file`);
    continue;
  }
  if (file === "scripts/check-public-source.mjs") continue;
  const text = execFileSync("git", ["show", `:${file}`], {
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (patterns.some((pattern) => pattern.test(text)))
    problems.push(`${file}: possible secret; inspect privately`);
}
if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log(
  `Checked ${files.length} staged source files: no secret patterns or forbidden artifacts found. This scan supplements manual staged-file review.`,
);
