# Security policy

## Reporting a vulnerability

Please **don't open a public issue** for security problems. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository. We aim to acknowledge reports within 5 working days.

Useful details: the affected file, the AI tool and prompt (if the issue is in generated output), and the impact.

## What counts

- Code in this repository (installers, PowerShell module, build scripts, workflows) that could leak secrets, execute unintended code, or escalate privileges
- Skill instructions or templates that lead AI tools to generate insecure automation, for example:
  - secrets written into files or logs
  - script injection through workflow inputs
  - missing approval gates on production
  - over-privileged identities
  - mutating operations without a preview

## Supported versions

Only the latest release is supported. Please confirm the issue on the latest version before reporting.

## Using the generated automation safely

- Review AI-generated code before running it, and run it in a non-production environment first.
- Keep production behind a GitHub environment with required reviewers.
- Grant the Power Platform application user the least privilege the operation needs.
- Prefer GitHub OIDC federation over long-lived client secrets, and rotate secrets you do use.
