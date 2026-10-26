---
name: brightdata-workato-recipes
description: Build, review, or refactor Workato recipes the way Bright Data's Business Applications team builds them, following our naming, folder layout, try/catch with the [CM] System Error Handling function, the function status contract, project properties, shared #Connections and description template. Use whenever the user asks to create, design, scaffold, fix, review or document a Workato recipe, function, API endpoint, webhook or scheduled job, or mentions recipe JSON, wk push/lint, Workato projects (Sales, Marketing, Finance, FinOps, Imagine AI, Product, Common Functions) or processes like DealHub, LinkedIn sync, DoiT or BrightMind.
---

# Bright Data Workato Recipe Builder

This skill produces Workato recipe JSON that matches how Eliran's team builds recipes in the Bright Data workspace. It is based on an export of 57 production recipes.

## Before writing anything

1. If `recipe-skills` (Workato Labs) is available, load `skills/recipe-skills/skills/workato-recipes/SKILL.md` and then the connector skill. It covers Workato syntax and gives you valid action and trigger names. This skill sits on top of it and covers **our house conventions**.
2. Read `references/conventions.md`. It covers naming, folders, descriptions, comments, properties and schedules.
3. Read `references/error-handling.md`. It is mandatory: every recipe uses it.
4. Check `references/workspace-inventory.md` and reuse existing connections, functions, tables and properties. Never invent a new connection when a shared one exists.
5. If the business process, ticket link, project folder or trigger is unclear, ask. One short round of questions is enough.

## Build workflow

1. **Design first.** Split the process into one `Main` (scheduler or orchestrator), one entry recipe (`API` or `Webhook`), and `Fun NNN` functions, one function per responsibility. Show the user the recipe list with names and folder before you generate JSON.
2. **Start from a template** in `templates/`:
   - `scheduled-orchestrator.recipe.json`: clock trigger, Asia/Jerusalem, calls functions and checks `status`
   - `function.recipe.json`: callable recipe that returns `{status, message}`
   - `api-endpoint.recipe.json`: API Platform endpoint with 400/200/500 responses
   - `webhook.recipe.json`: Workato webhook trigger
   - `catch-system-error.snippet.json`: the exact catch block to paste into any recipe
3. **Fill in the business steps** inside the `try`. Rules:
   - Give every step a `comment` that says what it does in business terms ("search contact by email", "status = Error (Fun 001)").
   - Each step's `as` is a unique 8-character hex id. Datapills reference it as `line`.
   - Renumber `number` sequentially (depth-first) after editing.
   - Put complex transforms in one `workato_custom_code.invoke_custom_ruby_code` step with a declared `code_input` schema and `code_output_schema_json`. Don't chain 10 formula steps.
   - Use `logger.log_message` with `"user_logs_enabled": "false"` for debug payloads at key points.
   - Read channel IDs, emails, Drive folders and IDs from `project_property` or `account_property` pills. Never hardcode them.
4. **Write the description** using the template in `conventions.md`. Include the Monday ticket link.
5. **Validate:**
   - `python3 scripts/check_conventions.py <files>` checks house style. Fix every ERROR and justify any remaining WARN.
   - `wk lint <file>` checks Workato syntax, if the CLI is installed.
6. **Deliver.** Save files to `recipes/<Project>/<Process folder>/<snake_case_name>.recipe.json`, named by the file-name rule. Give a short summary: the recipe list, call graph, properties to create, and connections used.
7. **Never run `wk push`** unless the user explicitly asks, and never against production without confirmation.

## Reviewing an existing recipe

Run `scripts/check_conventions.py`, then review in this order:

1. Error handling (try/catch → System Error Handling; function status checked by the caller)
2. Hardcoded secrets, channels and emails
3. Idempotency on retries and webhooks
4. Description and comments
5. Naming

Report findings as a table with columns Severity, Step, Issue and Fix.

## Hard rules

- No credentials, tokens or API keys in recipe JSON. They go in a connection or a project property. If you find one, flag it and tell the user to rotate it.
- `private: true`. `concurrency: 1` unless parallel runs are proven safe (parallel functions use 3–10).
- Time zone `Asia/Jerusalem` for schedules and `now.in_time_zone("Asia/Jerusalem")` for timestamps.
- Use official product names: Salesforce, HubSpot, Slack, monday.com, Bright Data.
