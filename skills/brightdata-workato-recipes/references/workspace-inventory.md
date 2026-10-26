# Workspace Inventory (export of 15/10/2026)

Reuse these assets. In `config`, reference a connection as:
`{"keyword":"application","provider":"<provider>","skip_validation":false,"account_id":{"zip_name":"<path>","name":"<name>","folder":"<folder>"}}`
For custom connectors, add `"custom": true` to `account_id`.

## Connections (#Connections)

| Provider id | Connection name | zip_name | Use for |
|---|---|---|---|
| salesforce | Salesforce - Automation User | #Connections/BizOps App/salesforce_automation_user.connection.json | All Salesforce work |
| slack_bot | Biz Admin Workbot | #Connections/Slack/biz_admin_workbot.connection.json | Bot messages, Block Kit, bot commands |
| slack_bot | SlackEntWorkbot | #Connections/Slack/slackentworkbot.connection.json | Enterprise workbot (rare) |
| slack | Biz Admin Slack | #Connections/Slack/biz_admin_slack.connection.json | Plain channel posts, admin |
| postgresql | PostgreSQL account | #Connections/BizOps App/postgresql_account.connection.json | Process DB (dealhub.*, marketing.*) |
| snowflake | Snowflake: ETL_SALESFORCE | #Connections/BizOps App/snowflake_etl_salesforce.connection.json | BI source data |
| hubspot | HubSpot | #Connections/Marketing/hubspot.connection.json | Marketing CRM |
| okta | Okta | #Connections/BizOps App/okta.connection.json | Identity / ELCM |
| zendesk | Zendesk | #Connections/BizOps App/zendesk.connection.json | Support |
| gong | Gong.io | #Connections/Marketing/gong_io.connection.json | Call data |
| linkedin | Linkedin API | #Connections/Marketing/linkedin_api.connection.json | LinkedIn native |
| rest | LinkedIn Marketing (custom) | #Connections/Marketing/linkedin_marketing_custom.connection.json | LinkedIn REST |
| rest | PartnerStack API | #Connections/Marketing/partnerstack_api.connection.json | PartnerStack |
| rest | PeerPanda API | #Connections/Marketing/peerpanda_api.connection.json | Competitor events |
| rest | DealHub | #Connections/BizOps App/dealhub.connection.json | DealHub API |
| rest | DoIt API | #Connections/FinOps/doit_api.connection.json | DoiT ingest |
| rest_secondary | Brightdata CP | #Connections/Brightdata/brightdata_cp.connection.json | Bright Data control panel API |
| brightdata_connector_5515774_1780900514 | Brightdata (custom) | #Connections/Brightdata/brightdata.connection.json | SERP / scraping |
| anthropic_connector_5515774_1766397514 | Anthropic API (custom) | #Connections/AI/anthropic_api.connection.json | Claude LLM steps |
| open_ai | OpenAI API | #Connections/AI/openai_api.connection.json | OpenAI LLM steps |
| monday_connector_5515774_1766397492 | Monday (custom) | #Connections/BizOps App/monday.connection.json | monday.com items |
| google_sheets | Google Sheet | #Connections/Google Apps/google_sheet.connection.json | |
| gmail | Gmail | #Connections/Google Apps/gmail.connection.json | |
| google_drive | Google Drive | #Connections/Google Apps/google_drive.connection.json | |
| workato_app | RecipeOps | #Connections/Workato Features/recipeops.connection.json | Job/recipe monitoring |

Ignore `My eighth HTTP account`; it is a leftover.

## Shared functions (Common Functions/Error Handling Process)

- `[CM] Fun | System Error Handling`: `cm_fun_system_error_handling.recipe.json`
- `[CM] Fun | Application Error Handling`: `cm_fun_application_error_handling.recipe.json`
- `Function: Add Project Details To Table`, `Function: Monday Error Handler` (internal to the above)

## Lookup tables, templates and API groups

- Lookup tables: `Error Handling Details` (error routing per recipe), `BRD Account Product`
- Message templates: `System Error - Slack Version`, `System Error - Slack Version Without Ticket details`
- API groups: `Brightdata CP` (handle `brightdata-cp`), `BrightMind Bot` (`brightbot`), `Prodcut` (`prodcut`)

## Data tables

| Table | Folder |
|---|---|
| sync_watermarks | FinOps/[DoiT] Cloud Cost Ingestion |
| dealhub_to_cp_sync | Finance/Billing/Salesforce To Brightdata CP/Dealhub CP Sync |
| blocked_countries | Marketing |
| fast5_snapshots | Sales/Sales Fast 5 |
| brightmind_whitelist_users, brightbot_thread_bus, slack_dynamic_home_buttons | Imagine AI/BrightdMind |
| competitors_global_events | Imagine AI/AI Events Hunter/PeerPanda |
| sf_automation_monitor_apss | Imagine AI/Automataion Tracking |
| auto_leads_table | Common Functions/Error Handling Process |

## Properties

- **Account:** Automation Admin Email, Automation Error Handling Channel, Environment, Monday Automation Monitoring Board, Salesforce Domain, BrightData SFDC Account Id, Biz Admin SDFC Contact Id
- **Common Functions:** Monday Task Enablement, Initial System Error Ticket Value, Initial Application Error Ticket Value, slack automation channel id, slack-automation-errors
- **Sales:** fast-5-for-sales-slack-channel, dh_contract analysis_GDrive, dh_contract analysis_channel, dh_final_contract_drafts_GDrive, dh_cro_user, dh_dealdesk_channel
- **Marketing:** hs formId, hs portalId, Linkedin event registration HS Form
- **Finance:** Dealhub manager sfdc user id, Dealub To CP Channel
- **Product:** datasets-deal-announcements channel, deep-lookup-prompts channel
- **Imagine AI:** workato automation tracking slack channel, compliance-weekly-insights-chanel_id, geo_buckets, pagination_page_index, slack_app_id, business-applications-monitoring-alerts-channel

## Reference recipes (best examples per pattern)

| Pattern | Recipe |
|---|---|
| Orchestrator + functions | `LS-01 \| Main \| LinkedIn Events → HubSpot Pipeline` |
| Function with watermark | `Fun-001 \| DoIt Process Digital Ocean` |
| Function status contract | `Fun-003 \| Send Events To DoIt` |
| API endpoint | `[BM]API-002 \| Check Bot Authorization` |
| Webhook + idempotency | `Webhook: Luma-to-HubSpot Guest Sync` |
| Application errors (bulk) | `Fun-1.1 \| Account Product Sync` |
| AI + Slack digest | `Scheduled: Fast5 for Sales — Weekly Gong Digest` |
| Best description | `Scheduled: Sync Customer Revenue Metrics`, `DH-01 \| Contract Intake & Registration` |
