# Cursor rules for InfiniLM-SVC

Project rules and agent skills used by Cursor in this repo.

## Rules / skills

- **reproduce-infinilm-svc-results.mdc** – Reproduce benchmark/deployment results for deployment cases (e.g. `cache-type-routing-validation`). Use when the user asks to reproduce, re-run, or validate results. Covers case selection, env vars, running `reproduce-results.sh` or case-specific scripts, model readiness, and comparing results.

Rules are applied automatically by Cursor based on their `description` and `globs`. They are stored under `.cursor/rules` and can be version-controlled.
