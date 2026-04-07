module.exports = async function upsertPrComment({ github, context, process }) {
  const fs = require("fs");

  const marker = "<!-- codex-smart-contract-audit -->";
  const prNumber = Number(process.env.PR_NUMBER);
  const reportPath = process.env.AUDIT_REPORT_JSON_PATH || "audit-report.json";
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));

  const lines = [
    marker,
    "## Codex Smart Contract Audit",
    "",
    `Status: **${process.env.OVERALL_STATUS}**`,
    "",
    "| Severity | Count |",
    "| --- | ---: |",
    `| Critical | ${process.env.CRITICAL} |`,
    `| High | ${process.env.HIGH} |`,
    `| Medium | ${process.env.MEDIUM} |`,
    `| Low | ${process.env.LOW} |`,
    `| Informational | ${process.env.INFORMATIONAL} |`,
    `| Blocked checks | ${process.env.BLOCKED_CHECKS} |`,
    "",
    `Artifacts: \`${process.env.ARTIFACT_NAME}\``,
    "",
    "The full markdown report and machine-readable JSON report are attached to this workflow run as artifacts."
  ];

  if ((report.blocked_checks || []).length > 0) {
    lines.push("");
    lines.push("Blocked checks:");
    for (const blocked of report.blocked_checks.slice(0, 3)) {
      lines.push(`- ${blocked.check}: ${blocked.reason}`);
    }
  }

  const body = lines.join("\n");
  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: prNumber,
    per_page: 100,
  });

  const existing = comments.find((comment) => comment.body && comment.body.includes(marker));
  if (existing) {
    await github.rest.issues.updateComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      comment_id: existing.id,
      body,
    });
  } else {
    await github.rest.issues.createComment({
      owner: context.repo.owner,
      repo: context.repo.repo,
      issue_number: prNumber,
      body,
    });
  }
};
