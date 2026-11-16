# Client capabilities and official sources

Checked 2026-11-16. This is a documentation contract audit, not a claim of live
end-to-end certification. Tests use synthetic payloads shaped by these references.
The packaged-gem smoke test verifies installation and runs the configured hooks
without logging user/session payloads. Codex commands resolve the git root (the Rails
app must be at that root); Gemini commands use `GEMINI_PROJECT_DIR`. Other clients
should start at the Rails app root. Project trust, hook approval, policy and runtime
versions remain client responsibilities.

## Primary clients

| Client | Documented capabilities / configuration | Official references |
|---|---|---|
| Claude Code | Skills in `.claude/skills/<name>/SKILL.md`; hooks in `.claude/settings.json`, grouped events, seconds timeout; Write/Edit input `tool_input.file_path`, exit 2 feedback. Instructions via CLAUDE.md or current AGENTS.md discovery. MCP uses project `.mcp.json`, `mcpServers`. | [Skills](https://code.claude.com/docs/en/skills), [hooks](https://code.claude.com/docs/en/hooks), [memory](https://code.claude.com/docs/en/memory), [MCP](https://code.claude.com/docs/en/mcp) |
| Codex CLI | `.agents/skills/<name>/SKILL.md`, AGENTS.md; `.codex/hooks.json` with grouped PascalCase events, seconds timeout. `apply_patch` input is `tool_input.command`, not a file_path; deny uses `hookSpecificOutput.permissionDecision`. File-tool matchers avoid shell/read calls; patch paths resolve against session cwd; Stop always emits JSON. MCP: `.codex/config.toml`, `[mcp_servers.<name>]`. Non-managed hooks need review/trust. | [Skills](https://learn.chatgpt.com/docs/build-skills), [hooks](https://learn.chatgpt.com/docs/hooks), [MCP](https://learn.chatgpt.com/docs/extend/mcp) |
| Copilot VS Code (Copilot harness), CLI and coding/cloud agent | `.github/skills/<name>/SKILL.md`, `.github/copilot-instructions.md`; `.github/hooks/*.json`, `version: 1`, flat camelCase events, `bash`, `timeoutSec`; input toolName/toolArgs (object or legacy JSON string). Pre-tool denial is top-level permissionDecision; post-tool additionalContext; agentStop decision:block. Cloud supports these events. VS Code's legacy Local harness is a separate format, not generated here. | [Customization](https://docs.github.com/en/copilot/reference/customization-cheat-sheet), [hook protocol](https://docs.github.com/en/copilot/reference/hooks-reference), [VS Code harness migration](https://code.visualstudio.com/docs/agent-customization/hooks) |
| Cursor Agent | AGENTS.md and `.cursor/skills`; `.cursor/hooks.json`, `version: 1`, flat camelCase events, seconds timeout. Generic preToolUse matches Write/Delete and emits explicit permission allow/deny; afterFileEdit supplies file_path but has no model-feedback response; stop uses followup_message and loop_count. Project hooks run at project root. MCP: `.cursor/mcp.json`, mcpServers. | [Skills](https://cursor.com/docs/skills), [rules](https://cursor.com/docs/rules), [hooks](https://cursor.com/docs/hooks), [MCP](https://cursor.com/docs/mcp) |
| Gemini CLI | GEMINI.md, `.gemini/skills` (also `.agents/skills` alias); `.gemini/settings.json` grouped hooks with BeforeTool/AfterTool/AfterAgent and **milliseconds** timeout. write_file/replace use file_path. BeforeTool/AfterTool match write_file/replace. BeforeTool and AfterAgent use decision deny and reason; AfterTool appends lint feedback via hookSpecificOutput.additionalContext, preserving the tool result. MCP: settings.json mcpServers. | [Skills](https://geminicli.com/docs/cli/skills/), [context](https://geminicli.com/docs/cli/gemini-md/), [hooks](https://geminicli.com/docs/hooks/reference/), [hook environment](https://geminicli.com/docs/hooks/#environment-variables), [file tools](https://geminicli.com/docs/tools/file-system/), [MCP](https://geminicli.com/docs/tools/mcp-server/) |

Copilot MCP differs by surface: VS Code uses `.vscode/mcp.json` with `servers`
([VS Code docs](https://code.visualstudio.com/docs/agent-customization/mcp-servers));
coding agent uses repository settings JSON with `mcpServers` and tool allowlists
([GitHub docs](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/configure-mcp-servers)).
No MCP server is installed by this gem. MCP offers tools, not an automatic check
on completion, and would add a second transport without strengthening the gates.

## Additional clients: narrower integration

| Client | Verified surface; what the harness installs | Official references |
|---|---|---|
| Cline | Native `.cline/skills` and `.clinerules/*.md`. Installs both. Cline has its own hooks; no adapter claimed. Global skills can override project skills. | [Skills](https://docs.cline.bot/customization/skills), [rules](https://docs.cline.bot/customization/cline-rules), [hooks](https://docs.cline.bot/customization/hooks) |
| Roo Code | `.roo/rules` and `.agents/skills` / `.roo/skills`. Installs rules and shared skill; no hook adapter claimed. | [Skills](https://roocodeinc.github.io/Roo-Code/features/skills/), [instructions](https://roocodeinc.github.io/Roo-Code/features/custom-instructions/) |
| Amp | AGENTS.md and `.agents/skills` supported; personal skills may mask repository skills. Installs shared skill and instructions; no hook adapter claimed. MCP is supported separately. | [Skills](https://ampcode.com/docs/customize/skills), [AGENTS.md](https://ampcode.com/docs/customize/agents-md), [MCP](https://ampcode.com/docs/customize/mcp) |
| Windsurf / Devin Desktop | Current documentation redirects to Devin Local: AGENTS.md, `.agents/skills` (legacy `.windsurf/skills` also read), `.devin/hooks.v1.json` and `.devin/mcp_config.json`. Installs shared skill/instructions only; does not pretend its hook format is Claude's. | [Current customizations](https://docs.devin.ai/desktop/devin-local/customizations) |
| Junie | `.junie/skills` in CLI/IDE; CLI prioritizes `.junie/AGENTS.md` over root AGENTS.md. Installs native skill, uses root guidelines and updates `.junie/AGENTS.md` only if it already exists. No hook adapter claimed. | [Skills](https://junie.jetbrains.com/docs/agent-skills.html), [guidelines](https://junie.jetbrains.com/docs/guidelines-and-memory.html) |
| JetBrains AI Assistant | `.aiassistant/rules/*.md`; rule type selected in IDE. Installs rule file; choose Always and inspect attached rules. This is distinct from Junie. No skills/hooks parity claimed. | [Project rules](https://www.jetbrains.com/help/ai-assistant/configure-project-rules.html) |
| Aider | YAML config: read, auto-test, test-cmd; test failure is sent back for repair. Installs a separate opt-in config so existing `.aider.conf.yml` is preserved. No native skills/hooks/MCP support assumed. | [Configuration](https://aider.chat/docs/config/aider_conf.html), [automatic lint/test](https://aider.chat/docs/usage/lint-test.html) |

## Verification and limits

- One neutral SKILL.md template renders identical client copies; configuration is
  in the packaged clients.json manifest. Frontmatter stays name/description only.
- All checks converge on bin/agent-check, including hooks and Aider auto-test.
- verify-install checks fully owned files and marked instruction blocks with SHA-256,
  plus managed hook command presence; unrelated user settings/text may change. Skill digests
  come from the source template, so a preserved divergent skill cannot pass.
  Digests never copy the contents of existing settings into another file.
- JSON with comments is intentionally rejected and preserved. No automatic trust,
  credential, global configuration or editor permission changes are performed.
- Pre-edit checks support documented file paths / Codex patch headers. Shell,
  arbitrary MCP edits, unsupported tool shapes, editor completions and legacy
  clients are not a filesystem security boundary. Unknown tools are ignored;
  malformed recognized arguments report an error. Client error/timeout policy
  may fail open, so CI is still needed.
- Cursor Delete maps to Edit: generated schemas are protected; existing migrations
  may be deleted, consistent with Codex patch deletion. Hook lint paths containing
  commas remain unsupported by the shared `--files` comma-separated interface.
- Gemini resolves duplicate skill names by precedence: `.agents/skills` wins over
  `.gemini/skills` within the workspace tier, rather than listing both copies.
  Native skill copies are retained for compatibility; shared Roo/Amp copies
  already use `.agents/skills` only.
- Reinstalling unchanged client hooks preserves settings formatting and timestamps.
- Stop guards allow the retry to finish, rather than producing unbounded loops.
  Hook success does not replace CI or prove that a client loaded its config.
- For a live check after approving hooks: ask the client to create a migration
  directly with its file tool (must be denied), generate it with Rails (allowed),
  introduce a lint error and finish (must report the failed check). Confirm
  rails-review appears in the client's skill list. No live runs are claimed here.
