#!/usr/bin/env python3
"""Check a Workato recipe JSON against Bright Data BizApps recipe conventions.

Usage: python3 check_conventions.py <recipe.json> [more.json ...]
Exit code 1 if any ERROR is found. WARNs do not fail.
Run this IN ADDITION to `wk lint` (which checks Workato syntax); this checks house style.
"""
import json, re, sys

SYS_ERR = "[CM] Fun | System Error Handling"
NAME_PATTERNS = [
    r"^[A-Z0-9]+-\d{2} \| (Main|Fun \d{3}|API \d{3}|Scheduler|Orchestrator) \| .+",  # DH-01 | Fun 001 | Name
    r"^(API|Webhook|Scheduled): .+",                                                  # API: Name
    r"^\[[A-Z0-9-]+\] ?.+",                                                           # [AI-EH] Fun-001 | Name
    r"^Fun-\d+(\.\d+)? \| .+",                                                        # Fun-001 | Name
]
SECRET_PATTERNS = [r"\"[A-Za-z_]*(token|secret|key)\":\s*\"[A-Fa-f0-9]{32,}\"",r"Bearer [A-Za-z0-9._-]{20,}", r"\bsk-[A-Za-z0-9]{20,}", r"xox[bpa]-[A-Za-z0-9-]{10,}",
                   r"(?i)\"(api[_-]?key|password|secret|token)\"\s*:\s*\"[^\"#=][^\"]{8,}\""]


def walk(step, parent=None):
    yield step, parent
    for child in step.get("block", []) or []:
        yield from walk(child, step)


def flow_name(step):
    fid = (step.get("input") or {}).get("flow_id")
    return fid.get("name") if isinstance(fid, dict) else str(fid)


def check(path):
    errors, warns = [], []
    d = json.load(open(path))
    code = d.get("code", {})
    name = d.get("name", "")
    trig = f"{code.get('provider')}.{code.get('name')}"
    is_function = trig == "workato_recipe_function.execute"
    is_api = code.get("provider") == "workato_api_platform"

    # R1 naming
    if not any(re.match(p, name) for p in NAME_PATTERNS):
        warns.append(f"Name '{name}' doesn't match a house pattern (e.g. 'DH-01 | Fun 001 | Name', 'API: Name', 'Scheduled: Name').")
    if re.search(r"(?i)schedual|automataion|massage", name):
        warns.append("Typo in name (schedual/automataion/massage).")

    # R2 description
    desc = d.get("description") or ""
    if len(desc.strip()) < 40 or desc.startswith("When there is"):
        errors.append("Description missing or auto-generated. Use the house template (Ticket, TRIGGER, PURPOSE, FLOW).")
    elif "monday.com" not in desc and "Ticket" not in desc:
        warns.append("Description has no Monday ticket link.")

    # R3 recipe settings
    if d.get("private") is not True:
        warns.append("Recipe should be private: true.")

    # R4 top-level try/catch
    top = [b.get("keyword") for b in code.get("block", []) or []]
    if top[-2:] != ["try", "catch"] and not (top and top[0] == "try"):
        errors.append(f"Top level must be a single try/catch wrapping all steps. Found: {top}.")
    catches = [s for s, _ in walk(code) if s.get("keyword") == "catch"]
    if not catches:
        errors.append("No catch block.")
    else:
        outer = catches[-1] if code.get("block") and code["block"][-1].get("keyword") == "catch" else catches[0]
        inner = list(walk(outer))
        calls_sys = any(s.get("provider") == "workato_recipe_function" and flow_name(s) == SYS_ERR for s, _ in inner)
        returns_err = any(s.get("name") == "return_result" and "Error" in json.dumps(s.get("input")) for s, _ in inner)
        api_resp = any(s.get("name") == "return_response" for s, _ in inner)
        if is_function:
            if not (returns_err or calls_sys):
                warns.append("Function catch must return_result status='Error' (or call System Error Handling).")
        elif not calls_sys:
            errors.append(f"Catch must call '{SYS_ERR}'.")
        if is_api and not api_resp:
            errors.append("API catch must return_response with an error status before/alongside error handling.")
        retry = (outer.get("input") or {}).get("max_retry_count")
        if retry not in (None, "0", 0):
            warns.append(f"Catch retries={retry}. House default is 0; make sure the steps are idempotent.")

    # R5 function contract
    if is_function:
        rs = (code.get("input") or {}).get("result_schema_json") or "[]"
        if "status" not in rs:
            warns.append("Function result schema must include 'status' (Success/Error) and 'message'.")
        if not any(s.get("name") == "return_result" for s, _ in walk(code)):
            warns.append("Function never calls return_result (OK only for fire-and-forget functions).")

    # R6 callers check function status
    for s, p in walk(code):
        if s.get("name") == "call_recipe" and flow_name(s) != SYS_ERR:
            ref = s.get("as")
            if ref and not re.search(r'line\W+' + re.escape(ref), json.dumps(code)):
                warns.append(f"Step {s.get('number')}: result of '{flow_name(s)}' is never checked (expect if status == 'Error' → stop with error).")

    # R7 clock timezone
    if code.get("provider") == "clock" and (code.get("input") or {}).get("time_unit") in ("days", "weeks") \
            and (code.get("input") or {}).get("timezone") != "Asia/Jerusalem":
        warns.append("Scheduler should set timezone 'Asia/Jerusalem'.")

    # R8 step comments
    acts = [s for s, _ in walk(code) if s.get("keyword") in ("action", "if", "foreach", "repeat") and s.get("provider") != "logger"]
    if acts:
        ratio = sum(1 for s in acts if s.get("comment")) / len(acts)
        if ratio < 0.8:
            warns.append(f"Only {ratio:.0%} of steps have a comment (target ≥80%).")

    # R9 hardcoded values that belong in properties
    raw = json.dumps(d, ensure_ascii=False)
    for m in re.findall(r'"channel": "(#[^"{][^"]*|C[A-Z0-9]{8,})"', raw):
        warns.append(f"Hardcoded Slack channel {m}. Use a project property.")
    for m in set(re.findall(r'[\w.+-]+@brightdata\.com', raw)):
        warns.append(f"Hardcoded email {m}. Use an account/project property.")

    # R10 secrets
    for pat in SECRET_PATTERNS:
        if re.search(pat, raw):
            errors.append(f"Possible secret in recipe (pattern {pat}). Move to a connection.")

    # R11 connections
    for c in d.get("config", []):
        if c.get("provider") in ("salesforce", "slack_bot", "slack", "postgresql", "hubspot") and not c.get("account_id"):
            warns.append(f"No connection bound for '{c['provider']}'. Use the shared one in #Connections.")

    return errors, warns


def main():
    bad = 0
    for p in sys.argv[1:]:
        try:
            e, w = check(p)
        except Exception as ex:  # noqa
            e, w = [f"Could not parse: {ex}"], []
        status = "FAIL" if e else ("WARN" if w else "PASS")
        print(f"[{status}] {p}")
        for x in e: print(f"   ERROR: {x}")
        for x in w: print(f"   WARN:  {x}")
        bad += bool(e)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
