# workato-automations

Bright Data Workato assets (Brightdata workspace, ID 5450934) under version control.

## Branches = Workato environments

| Branch | Workato env | Notes |
|---|---|---|
| `dev` (default) | dev | Build and test here |
| `qa` | test | Not in use yet |
| `prod` | prod | Mirror of what runs in prod; change only via PR |

Promote by PR: `dev` → `qa` → `prod`.

## Layout

- `manifests/automations/prod-env-home/` – export of the prod environment
- `automations/` – `wk` CLI projects (`.wk/` local state is not committed)
- `skills/brightdata-workato-recipes/` – Bright Data recipe-building skill
- `wk/`, `skills/recipe-skills/` – upstream `workato-devs` repos as git submodules

## Setup

```bash
git clone --recurse-submodules https://github.com/elirans-brd/workato-automations.git
cd workato-automations
git config core.hooksPath .githooks   # enables the pre-commit secret scan
```

Workato CLI profiles (one per environment, stored in the macOS Keychain):

```bash
wk auth login --environment dev  --name dev
wk auth login --environment prod --name prod   # read-only API client
wk auth list
```

`profiles.env` (file-based credentials for CI) is git-ignored and must never be committed.

## Secrets

Never hardcode tokens in recipes. Store them in Workato account/environment properties.
`scripts/check-secrets.py` runs on every commit; run it on the whole repo with:

```bash
python3 scripts/check-secrets.py --all
```
