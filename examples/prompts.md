# Prompt library

Copy, adjust the names, and send. You don't need to mention the skill: it activates on Power Platform requests. Add scale and risk details ("about 50k records", "production") for better designs. See the [user guide](../docs/user-guide.md) for how to phrase requests for each skill specifically.

The first five sections below are for `power-platform-alm-toolkit` (generates code for you to commit). The four sections after that are for the live agents — they act now, or generate a ready-to-run equivalent.

## Data & Schema Management

- "Generate a data dictionary for every custom table in the **Sales** solution: table, column, type, required level, description, choice values. Output Markdown and CSV, and let BAs run it from GitHub."
- "We need to set `contoso_region` on ~80,000 accounts based on their country field. Build a safe bulk-update module with a preview and an undo."
- "Compare the schema of the **Projects** tables between test and production and report columns that exist in one but not the other."
- "Create a schema migration that renames the display names of 15 columns across 3 tables, deployed through our pipeline rather than by hand."

## Access & Profile Administration

- "Sync users' security roles from a CSV (UPN, role name) to dev, test and prod. Show differences first, then apply."
- "Audit every environment for users with System Administrator or System Customizer and publish the report as a job summary every Monday."
- "When someone joins the *Finance-PowerPlatform* Entra group, they should get the **Finance User** role in prod. Design it."
- "Disable Dataverse users whose Entra accounts are disabled, with a dry run and an undo."

## Automation & Workflow Governance

- "Before release weekends, switch off every flow in the **Invoicing** solution in prod, then turn back on only the ones that were on before."
- "List every cloud flow that failed more than 10 times in the last 7 days across our environments and who owns it."
- "Give admins a button to disable a specific plug-in step in production during an incident, with approval and an automatic log."
- "Find flows owned by users who've left the company and reassign them to a service account."

## Environment Operations

- "Just the pipeline: export **HRCore** from dev into Git, promote to UAT then prod, with a different SharePoint site URL per environment and a SharePoint connection reference. Prod needs a manager's approval."
- "Map every dependency that blocks uninstalling **LegacyCRM** and turn it into a migration checklist."
- "We use Dataverse Git integration (YAML format). Adapt the build pipeline so it packs from our repo layout."
- "Create a nightly job that backs up production and verifies the backup exists, with a Teams notification if it doesn't."

## Connectors, Custom APIs and micro-frontends

- "Wrap our internal pricing REST API as a custom connector with Entra ID auth, packaged in a solution and deployed by pipeline."
- "Create a Dataverse Custom API `contoso_RecalculateQuotes` that a Power App button can call, including the plug-in skeleton and solution packaging."
- "Build a PCF dataset control that shows records as a Kanban board, with the build wired into our pipeline."

## Quick questions (the skill answers directly, no full blueprint)

- "What's the PAC CLI command to unpack a solution with both managed and unmanaged?"
- "Which `import-solution` input makes the action use my deployment settings file?"
- "How do I turn off a cloud flow through the Dataverse Web API?"

---

## Live agent: `pp-data-ops-agent` (queries and bulk record changes)

- "How many contacts have no email address?"
- "Show me the 10 most recently created accounts."
- "Deactivate every case open over 90 days, with a preview first."
- "Update the status on every open opportunity older than a year to 'At Risk', after you show me what would change."
- "Delete the 5 test records we created yesterday with 'TEST-' in the name." *(deletes get their own separate confirmation)*

## Live agent: `pp-governance-agent` (security roles, connection references, flow health)

- "Audit security role drift between our dev and prod environments."
- "Why won't my flows turn back on after the solution import?"
- "Health check my environment." *(runs all three checks: role drift, connection references, flow health)*
- "Does anyone have System Administrator in prod who shouldn't?"
- "Check our connection references after the UAT import — I think a few are broken."

## Live agent: `pp-migration-agent` (environment copy, tenant migration, record/legacy data)

- "Copy our dev environment into a new UAT sandbox."
- "We're acquiring another company and need to move their entire Dataverse tenant into ours."
- "Move these accounts, their contacts, and their open opportunities to the new environment, keeping the relationships intact."
- "Move all 'VIP' tagged accounts from our old regional environment into our consolidated one, not the whole environment."
- "We're migrating our data from an old CRM system into Dataverse — I can export it to CSV first."

## Live agent: `pp-integration-agent` (external platform connectors and sync)

- "Connect Dataverse to our CRM so contacts and accounts stay in sync."
- "We want invoices created in Dataverse to show up in our accounting system automatically."
- "We need this to sync continuously, not just once a day."
- "We're expecting a high volume of orders per minute and need no duplicates even if something retries."
- "Can you store the connection details and keep a log of every sync, plus a queue so failed syncs retry?"
