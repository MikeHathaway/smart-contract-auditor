module.exports = async function upsertPrComment({ github, context, process }) {
  const fs = require("fs");

  const marker = "<!-- codex-smart-contract-audit -->";
  const prNumber = Number(process.env.PR_NUMBER);
  const reportPath = process.env.AUDIT_REPORT_JSON_PATH || "audit-report.json";
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const runUrl = process.env.WORKFLOW_RUN_URL;

  const findings = Array.isArray(report.findings) ? report.findings : [];
  const blockedChecks = Array.isArray(report.blocked_checks) ? report.blocked_checks : [];

  const summarizeFinding = (finding) => {
    const severity = String(finding.severity || "unknown").toUpperCase();
    const title = finding.title || "Untitled finding";
    const fileRef = Array.isArray(finding.files) && finding.files.length > 0
      ? finding.files
          .slice(0, 2)
          .map((file) => {
            if (!file || !file.path) return null;
            return file.line ? `${file.path}:${file.line}` : file.path;
          })
          .filter(Boolean)
          .join(", ")
      : "";
    const sourceSkills = Array.isArray(finding.source_skills) && finding.source_skills.length > 0
      ? ` [${finding.source_skills.join(", ")}]`
      : "";
    const location = fileRef ? ` (${fileRef})` : "";
    return `- **${severity}** ${title}${location}${sourceSkills}`;
  };

  const topBySeverity = (severity, limit) =>
    findings.filter((finding) => finding.severity === severity).slice(0, limit);

  const criticalFindings = topBySeverity("critical", Number.MAX_SAFE_INTEGER);
  const highFindings = topBySeverity("high", Number.MAX_SAFE_INTEGER);
  const mediumFindings = topBySeverity("medium", Number.MAX_SAFE_INTEGER);
  const inlineFindings = [...criticalFindings, ...highFindings, ...mediumFindings];
  const maxInlineFindings = 20;
  const shownFindings = inlineFindings.slice(0, maxInlineFindings);
  const hiddenFindingsCount = inlineFindings.length - shownFindings.length;
  const shownBlockedChecks = blockedChecks.slice(0, 5);
  const hiddenBlockedChecksCount = blockedChecks.length - shownBlockedChecks.length;

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
    `Artifacts: \`${process.env.ARTIFACT_NAME}\``
  ];

  if (runUrl) {
    lines.push(`Workflow run: ${runUrl}`);
  }

  lines.push("");
  lines.push("The full markdown report and machine-readable JSON report are attached to this workflow run as artifacts.");

  if (shownFindings.length > 0) {
    lines.push("");
    lines.push("<details open>");
    lines.push("<summary>Critical / High / Medium Findings</summary>");
    lines.push("");
    for (const finding of shownFindings) {
      lines.push(summarizeFinding(finding));
    }
    if (hiddenFindingsCount > 0) {
      lines.push(`- +${hiddenFindingsCount} more critical/high/medium finding(s) in \`audit-report.md\``);
    }
    lines.push("");
    lines.push("</details>");
  }

  if (shownBlockedChecks.length > 0) {
    lines.push("");
    lines.push("<details>");
    lines.push("<summary>Blocked checks</summary>");
    lines.push("");
    for (const blocked of shownBlockedChecks) {
      lines.push(`- ${blocked.check}: ${blocked.reason}`);
    }
    if (hiddenBlockedChecksCount > 0) {
      lines.push(`- +${hiddenBlockedChecksCount} more blocked check(s) in \`audit-report.md\``);
    }
    lines.push("");
    lines.push("</details>");
  }

  let body = lines.join("\n");
  const maxBodyChars = 12000;
  if (body.length > maxBodyChars) {
    body = [
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
      ...(runUrl ? [`Workflow run: ${runUrl}`] : []),
      "",
      "Comment truncated for size. Open the workflow run artifacts for the full report."
    ].join("\n");
  }

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
