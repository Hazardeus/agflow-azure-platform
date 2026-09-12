---
applyTo: "**/*.bicep,**/*.bicepparam"
---

# Bicep-specific instructions

When working with Bicep:

- Use the Bicep MCP tools when useful for:
  - resource schemas;
  - API versions;
  - diagnostics;
  - Bicep best practices;
  - Azure Verified Modules metadata.
- Never guess resource properties or API versions.
- Run diagnostics after changes.
- Keep modules focused on one infrastructure responsibility.
- Keep environment-specific configuration in `.bicepparam`.
- Never place secrets in parameters committed to Git.
- Prefer symbolic resource references over manually constructed resource IDs.
- Use outputs only when another infrastructure component needs them.
- Avoid unnecessary dependencies.
- Avoid premature abstraction.
- Do not deploy resources without explicit approval.