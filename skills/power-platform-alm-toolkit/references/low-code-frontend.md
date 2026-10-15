# Low-code trigger surface (Canvas App + Power Automate)

An optional alternative to the GitHub Actions `workflow_dispatch` form, for operators who would
rather stay inside Power Platform than go to GitHub to run an operation. Offer this *alongside*
the GitHub form, not instead of it — the GitHub form needs no extra setup and no Premium
licensing; this does.

## Why this needs Premium licensing

Firing a GitHub Actions run from Power Automate means calling GitHub's REST API, which requires
the **HTTP** action — a Premium connector. Don't propose this path without saying so; it's a
real cost/licensing decision for the user, not a detail to skip past.

## Canvas App screen (mirrors the GitHub form's inputs exactly)

One screen, matching the same inputs the GitHub `workflow_dispatch` form already defines for the
module — don't invent a different input set for the two trigger surfaces:

- A **dropdown** for environment (`dev` / `test` / `production`, same `choices` as the GitHub
  form's `environment` input).
- A **toggle** for "Test run (changes nothing)", defaulted **on**, same as the GitHub form.
- One **text input or dropdown per module-specific field**, in the same order and with the same
  labels as the GitHub form's inputs table (Part 4 of the blueprint) — a maker switching between
  the two surfaces shouldn't have to learn a second set of labels.
- A **Submit** button.
- A **label** bound to the flow's response, showing success/failure and a link to the GitHub
  Actions run for the full log.

## The flow: Canvas App → Power Automate → GitHub, with the secret never touching the app

1. **Trigger**: `PowerApps (V2)` trigger, with one input parameter per Canvas App field above.
2. **Get the dispatch token**: an **Azure Key Vault** connector action, `Get secret`, naming the
   secret that holds a GitHub token scoped to fire `repository_dispatch` on this repo (a
   fine-grained PAT or a GitHub App installation token — never a broad-scope classic PAT). The
   Canvas App and the maker never see this value; only the flow fetches it, at run time.
3. **Fire the dispatch event**: an **HTTP** action —

   ```
   POST https://api.github.com/repos/<owner>/<repo>/dispatches
   Authorization: Bearer @{outputs('Get_secret')?['body/value']}
   Accept: application/vnd.github+json
   Content-Type: application/json

   {
     "event_type": "<module-name>-dispatch",
     "client_payload": {
       "environment": "@{triggerBody()['environment']}",
       "test_run": "@{triggerBody()['test_run']}"
     }
   }
   ```

   Map every module-specific field from the Canvas App into `client_payload` the same way.
4. **Respond to the Canvas App** with the HTTP action's status and a constructed link to the
   repo's Actions tab, so the operator can watch the run without needing push access to trigger
   it themselves.

## The GitHub Actions side

Add a `repository_dispatch` trigger alongside the existing `workflow_dispatch` one, mapping the
same `client_payload` fields to the same job inputs the `workflow_dispatch` version already
uses — the pipeline's actual steps (unpack, validate, pack, deploy) don't change at all; only
how the run gets started differs:

```yaml
on:
  workflow_dispatch:
    inputs:
      # ...existing inputs, unchanged
  repository_dispatch:
    types: [<module-name>-dispatch]
```

Inside the job, read `github.event.client_payload.<field>` instead of `github.event.inputs.<field>`
when the trigger was `repository_dispatch` — or normalize both into one set of step-level
variables near the top of the job so the rest of the pipeline doesn't need to know which trigger
fired it.
