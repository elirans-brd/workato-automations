# House Conventions

These conventions come from 57 recipes in the Bright Data Workato workspace. The newest processes (DH-xx DealRoom and LS-01 LinkedIn) set the standard. Older recipes deviate.

## 1. Project and folder layout

```
<Project>/                         Business domain: Sales, Marketing, Finance, FinOps, Product,
                                    Imagine AI, Business Application Team
  <Process folder>/                One folder per business process, e.g. "DealHub/DealRoom Contract Analysis"
    Triggers/                      Optional: API, Slack bot command and webhook entry recipes
    <table>.workato_db_table.json  Data tables live next to the process that owns them
  properties.project_properties.json
Common Functions/                  Shared functions ([CM] ...). Never duplicate them
#Connections/<Group>/              ALL connections: AI, Brightdata, BizOps App, FinOps,
                                    Google Apps, Marketing, Slack, Workato Features
```

Put new connections only under `#Connections/<Group>/`. Don't put them in project folders.

## 2. Recipe names

Preferred pattern for multi-recipe processes:

| Role | Name | File name |
|---|---|---|
| Orchestrator / scheduler | `LS-01 \| Main \| LinkedIn Events → HubSpot Pipeline` | `ls_01_main_linkedin_events_hubspot_pipeline.recipe.json` |
| Entry step | `DH-01 \| Contract Intake & Registration` | `dh_01_contract_intake_registration.recipe.json` |
| Function | `DH-03 \| Fun 001 \| Analysis & Delivery` | `dh_03_fun_001_analysis_delivery.recipe.json` |
| API endpoint | `DH-05 \| API 001 \| CRO Approve` | `dh_05_api_001_cro_approve.recipe.json` |
| Shared function | `[CM] Fun \| System Error Handling` | `cm_fun_system_error_handling.recipe.json` |

- `<CODE>` is a 2–5 letter process code (DH, LS, ELCM, AI-EH, BM). The number is the stage of the flow.
- Function numbers are 3 digits (`Fun 001`). Sub-steps use `Fun 002-1`.
- Standalone single recipes use `API: <Name>`, `Webhook: <Name>` or `Scheduled: <Name>`.
- File name: lowercase snake_case of the name, punctuation removed, `|` → `_`.
- Check spelling. The workspace already has "Schedualed", "Automataion" and "Massage". Don't add more.

## 3. Recipe description template (Markdown)

```markdown
# <Recipe name>

**📋 Ticket:** [<ticket title>](https://brightdata-group.monday.com/boards/<board>/pulses/<id>)

---

**TRIGGER:** <what starts it, incl. schedule + Asia/Jerusalem>

**PURPOSE:** <one sentence business outcome>

**FLOW:**
1. <step> → <system>
2. ...

**DB / TABLES:** `schema.table` (what is read and written)
**UPSTREAM:** <caller>
**DOWNSTREAM:** <functions called>

## Important logic
- <non-obvious rules: dedup keys, ON CONFLICT behaviour, pagination stop rule, idempotency>
```

For sync recipes with field mappings, add a `| Source field | Target field |` table (see `Scheduled: Sync Customer Revenue Metrics`).

## 4. Step comments

- Give every action, if and foreach a `comment` in business words: `last_processed_date`, `search contact by email`, `if contact is not present`, `status = Error (Fun 001)`.
- For if/else branches, the comment states the condition: `records exist` / `records doesn't exist`.
- For SQL steps, the comment names the table or view: `BI__DIGITAL_OCEAN_BILLING_INSIGHTS`.

## 5. Settings

| Setting | Default | When to change |
|---|---|---|
| `private` | `true` | never |
| `concurrency` | `1` | 3–10 for stateless functions called in a foreach (e.g. Refiner 10, SERP 3); 15 for high-traffic API endpoints |
| Catch `max_retry_count` | `"0"` | 1–2 only for idempotent external calls, with `retry_interval` 5–10 |

## 6. Schedules (clock.scheduled_event)

```json
{"time_unit": "days", "trigger_every": "1", "trigger_at": "07:00:00.000", "timezone": "Asia/Jerusalem"}
{"time_unit": "weeks", "trigger_every": "1", "days_of_week": "0", "trigger_at": "12:00:00.000", "timezone": "Asia/Jerusalem"}
```

Always set `timezone`. Business days in Israel are Sun–Thu (`days_of_week` 0–4).

## 7. Properties, not hardcoding

- **Account properties** (workspace-wide): `Environment`, `Salesforce Domain`, `Automation Admin Email`, `Automation Error Handling Channel`, `Monday Automation Monitoring Board`, `BrightData SFDC Account Id`, `Biz Admin SDFC Contact Id`.
- **Project properties**: Slack channel IDs, Google Drive folder IDs, HubSpot form and portal IDs, user IDs, feature flags.
- Pill syntax: `#{_dp('{"pill_type":"project_property","property_name":"dh_dealdesk_channel"}')}`.
- Property naming: lowercase with a process prefix, e.g. `dh_dealdesk_channel`, `ls_hubspot_form_id`. Avoid spaces in new properties.

## 8. Data storage choice

| Need | Use |
|---|---|
| Small config or state (watermarks, whitelists, blocked lists) | Workato Data Table (`workato_db_table`) |
| Static mapping and error-routing metadata | Lookup table |
| Process records, audit and history (DealHub, LinkedIn) | PostgreSQL (`PostgreSQL account`), schema per domain: `dealhub.*`, `marketing.*` |
| Analytics source | Snowflake (`Snowflake: ETL_SALESFORCE`) |
| Temporary in-job lists | `workato_variable.declare_list`, or `workato_smart_list` for large lists |

Incremental syncs keep a **watermark** row (see `sync_watermarks` in FinOps), update it only after success, and fail loudly if it is stale for more than N days.

## 9. Patterns we reuse

- **Orchestrator → functions:** Main calls `Fun 001..N` with `call_recipe` (sync) when order matters. It uses `call_recipe_async` + `wait_for_async_jobs` for fan-out.
- **Function result check:** after every `call_recipe`, add `if result.status == "Error"` → `stop` with error and `result.message`.
- **Bulk sync:** fetch → batch (200 for Salesforce) → bulk upsert → collect failures in a list → Application Error Handling with failed record IDs.
- **AI steps:** use the Anthropic custom connector (`Anthropic API`) or OpenAI. Put the prompt in a Ruby step or a property, parse with `json_parser`, and validate fields before use.
- **Slack output:** post as `Biz Admin Workbot` (`slack_bot.post_bot_message`) and build Block Kit in a Ruby step. Use `Biz Admin Slack` only for admin and channel operations.
- **Web data:** use the Bright Data custom connector (`Brightdata`) for SERP and scraping.
