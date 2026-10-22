# Using the skill in chat assistants

Chat assistants without native skill folders can still use this skill. Give them two files from the [latest release](../../../releases/latest), or build them yourself with `python3 scripts/build.py` (they appear in `dist/portable/`):

| File | What it is | Where it goes |
|---|---|---|
| `power-platform-alm-toolkit.instructions.md` | Short system instructions (about 1,800 characters) | The assistant's **instructions** box |
| `power-platform-alm-toolkit.md` | The complete skill in one file: SKILL.md plus every reference and the PowerShell module | Upload as a **knowledge** file |

The instructions tell the assistant to treat the knowledge file as its operating manual, follow the four-part blueprint, and look up exact commands before writing code.

Menu names in these products change often. If a step below doesn't match what you see, look for the equivalent "instructions" and "knowledge/files" settings.

## ChatGPT (custom GPT)

Requires a ChatGPT plan that can create GPTs.

1. Go to **Explore GPTs → Create**, then switch to the **Configure** tab.
2. **Name:** `Power Platform ALM Architect`. **Description:** `Generates Power Platform automation modules with pipelines and runbooks.`
3. **Instructions:** paste the full contents of `power-platform-alm-toolkit.instructions.md`.
4. **Knowledge:** upload `power-platform-alm-toolkit.md`.
5. **Capabilities:** turn on *Web search* (lets it check current docs) and *Code interpreter* (lets it produce downloadable files).
6. Save. Choose *Only me*, *Anyone with the link*, or your workspace.

> On ChatGPT desktop and Codex, you can also use the native skill. See the [installation guide](installation.md).

## Google Gemini (Gems)

1. Open Gemini → **Gems** → **New Gem**.
2. **Name:** `Power Platform ALM Architect`.
3. **Instructions:** paste `power-platform-alm-toolkit.instructions.md`.
4. **Knowledge:** add `power-platform-alm-toolkit.md` as a file.
5. Save, and start a chat with the Gem.

> Using **Gemini CLI**? Install the native skill instead: `./scripts/install.sh --tool gemini`.

## Microsoft Copilot Studio (agent for your organisation)

A good fit when you want citizen developers to ask for operations in Teams or Microsoft 365 Copilot.

1. In Copilot Studio, **Create → New agent**, then skip to **Configure**.
2. **Name:** `Power Platform Ops Assistant`.
3. **Instructions:** paste `power-platform-alm-toolkit.instructions.md`.
4. **Knowledge → Add knowledge → Files:** upload `power-platform-alm-toolkit.md`.
5. Test in the side panel ("Explain how you would turn off all flows in a solution safely"), then **Publish** to Teams or Microsoft 365 Copilot.
6. Optional: add a tool or flow that triggers the toolkit's GitHub `workflow_dispatch` runbooks. The agent can then fill the form for operators, and the GitHub test-run and approval gates still apply.

Keep the agent's own permissions read-only unless you deliberately wire in actions. It's a design assistant, not an admin account.

## Claude Projects

If you can't upload skills (or want the skill scoped to one project):

1. Create a **Project**, open **Project knowledge**, and upload `power-platform-alm-toolkit.md`.
2. Paste `power-platform-alm-toolkit.instructions.md` into **Project instructions**.

Where skill upload is available, prefer it (`power-platform-alm-toolkit.zip` in Settings → Capabilities). It loads the skill only when needed, which keeps conversations shorter.

## Any other model, API or local LLM

Use `power-platform-alm-toolkit.instructions.md` as the system prompt and include `power-platform-alm-toolkit.md` as context. Example with an OpenAI-compatible API:

```python
from pathlib import Path
from openai import OpenAI

system = Path("power-platform-alm-toolkit.instructions.md").read_text()
skill = Path("power-platform-alm-toolkit.md").read_text()

client = OpenAI()
reply = client.chat.completions.create(
    model="<your-model>",
    messages=[
        {"role": "system", "content": system + "\n\n<knowledge file='power-platform-alm-toolkit.md'>\n" + skill + "\n</knowledge>"},
        {"role": "user", "content": "Build a module that syncs security roles from a CSV across dev, test and prod."},
    ],
)
print(reply.choices[0].message.content)
```

The bundle is about 70 KB (around 18k tokens), so use a model with a context window of at least 32k tokens.
