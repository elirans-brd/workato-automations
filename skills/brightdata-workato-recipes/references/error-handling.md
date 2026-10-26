# Error Handling (mandatory)

Every recipe follows the same shape:

```
trigger
└─ try
│    <all business steps>
└─ catch (max_retry_count "0", retry_interval "2")
     <error path depends on recipe type, see below>
```

Nothing goes outside the try. The only exception is a `logger` step that logs function input before the try.

## 1. System errors: `[CM] Fun | System Error Handling`

Use this for any unexpected failure (connector error, timeout, stop-with-error). Paste `templates/catch-system-error.snippet.json` and replace `<CATCH_AS>` with the catch step's `as` id everywhere.

- Call: `workato_recipe_function.call_recipe_async`. Use sync `call_recipe` only when the recipe must wait.
- `flow_id` → `{"zip_name": "Common Functions/Error Handling Process/cm_fun_system_error_handling.recipe.json", "name": "[CM] Fun | System Error Handling", "folder": "Common Functions/Error Handling Process"}`
- `ErrorDetails` mapping:

| Field | Value |
|---|---|
| parentProcessName | `"None"` for top-level recipes; job_context `recipe_name` when called from a parent |
| recipe_id | job_context `recipe_id` |
| processName | job_context `recipe_name` |
| process_path | job_context `recipe_path` |
| jobUrl | job_context `job_url` |
| is_repeat | job_context `is_repeat` |
| job_uuid | job_context `job_id` |
| error_uuid / errored_app / errored_action / error_step_number / errorType / errorMessage | catch output `uuid` / `adapter` / `action` / `line_number` / `type` / `message` |
| Timestamp | `=now.in_time_zone("Asia/Jerusalem")` |

The handler looks up the recipe in the **Error Handling Details** lookup table (Project_Domain, Folder_Name, Recipe_Id, Recipients, Slack_Channel, Owner, ticket flags). It posts to Slack using the `System Error - Slack Version` template and can open a monday.com ticket. **For a new recipe, tell the user to add a row to that lookup table**, or the function auto-adds a default row.

## 2. Application (business) errors: `[CM] Fun | Application Error Handling`

Use this when the run "succeeded" but some records failed business rules, such as account not found or a validation error. Collect failures in a list during the run. At the end, if the list is present, call:

```json
"parameters": {
  "recipe_details": { "parent_process_name", "recipe_id", "process_name", "process_path",
                      "job_url", "is_repeat", "Timestamp" },   // job_context pills
  "ErrorDetail": [ { "Timestamp", "Step", "System", "RecordsUniqueId",
                     "ErrorMassage", "AdditionalInformation",
                     "errorHandlingType": "Application Error" } ],
  "MoreDetails": [ { "label", "value" } ],   // optional
  "files":       [ { "fileName", "fileContent" } ]   // optional
}
```

The handler builds a CSV of failures and emails the recipients and owner from the lookup table. Note: `ErrorMassage` is the real field name; keep the typo.

## 3. Functions: status contract

Functions don't alert on their own. They return the error to the caller:

- `result_schema_json` must include `status` (`Success` | `Error`) and `message`, plus any data fields.
- End of try: `return_result` with `status: "Success"`.
- Catch: `return_result` with `status: "Error"` and `message` = catch `message`.
- Caller: right after `call_recipe`, add `if result.status equals "Error"` → `stop` with `stop_with_error: "true"` and `stop_reason` = `result.message`. The caller's own catch then calls System Error Handling once, at the top of the chain, so there are no duplicate alerts.

A function may call System Error Handling itself only if it is the top of its chain (scheduled through a function, or fire-and-forget async).

## 4. API endpoints

- Validate input first. If required params are blank → `return_response` 400 `{reason}` → `stop` without error.
- Catch → `return_response` 500 (403 for auth checks) with `"reason": "Error: <catch message>"`, **then** call System Error Handling.
- Declare every status code you return under `response.responses` in the trigger.
- Endpoints live in an API group (`Brightdata CP`, `BrightMind Bot`, `Prodcut`). Path is kebab-case.

## 5. Webhooks

- Make the handler idempotent. Webhooks retry, so dedup on the event ID (data table or Postgres `ON CONFLICT DO NOTHING`).
- In the catch you may filter known non-errors before calling System Error Handling (see the Luma webhook ignoring "Submission from this email address are not allowed").

## 6. Stop vs error

- Expected "nothing to do" → `stop` with `stop_with_error: "false"`.
- Data problem that needs a human → `stop` with `stop_with_error: "true"` and a readable multi-line `stop_reason` (🚨 headline, bullets with process, source and values). It flows into the catch → Slack.
