# Regression suite (Playwright: 9 API + 4 UI tests)

Targets: `app` (whatever Route 53 serves), `syd`, `mel`.

```bash
make test TARGET=app          # local
gh workflow run regression.yml -f target=mel   # GitHub (no AWS credentials needed)
```

What it proves:
- **API**: healthz, ready (db ok), info (region + pod), list, validation (empty / > 200 chars -> 400),
  404 for unknown id, create-read-delete round trip on a writable region, **503 on a read-only
  standby**, HTTP -> HTTPS redirect.
- **UI**: page renders the serving region, security headers (CSP, nosniff, frame deny), SPA deep
  links, add-item flow (or the standby message on a read-only region).

Run it: after `up`, after every drill's recovery, and against `mel` after `promote-replica`
(Melbourne must then pass the full writable path).

Failures: open the HTML report artifact (`playwright-report-<target>`) - traces and screenshots
are kept for failed tests.
