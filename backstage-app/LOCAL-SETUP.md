# Running this Backstage instance locally

This app was scaffolded with `@backstage/create-app` and wired into the
observability stack. A few environment gotchas were resolved during setup —
documented here so the run is reproducible.

## Prerequisites (important)

- **Node 22** (set as the nvm default during setup). Node 20.x does **not** work:
  `isolated-vm` (used by the scaffolder) needs a V8 API (`v8::SourceLocation`)
  that only exists in Node 22's V8.
  ```bash
  nvm use 22   # or: nvm alias default 22
  ```
- **macOS native builds**: on macOS 26 the Command Line Tools clang doesn't find
  the libc++ headers, so `better-sqlite3`/`isolated-vm` fail to compile with
  `'climits' file not found`. Export the SDK include path before any install/rebuild:
  ```bash
  export SDKROOT="$(xcrun --show-sdk-path)"
  export CPLUS_INCLUDE_PATH="$SDKROOT/usr/include/c++/v1"
  ```
  If you ever see that error again: `yarn rebuild better-sqlite3 isolated-vm`.

## Start it

The Grafana service-account token lives in `grafana.env` (created against the
local Grafana). Source it so the backend can reach Grafana through the proxy:

```bash
cd backstage-app
set -a; source ./grafana.env; set +a     # exports GRAFANA_URL + GRAFANA_TOKEN
yarn start                                # frontend :3001, backend :7007
```

Open **http://localhost:3001** and click **Enter** (guest sign-in). Port 3001 was
chosen so it doesn't clash with Grafana on :3000.

## What's wired in

- **Port 3001** — `app.baseUrl` + `backend.cors.origin` in `app-config.yaml`.
- **Grafana plugin** (`@backstage-community/plugin-grafana`, new frontend system):
  `grafanaPlugin` added to `packages/app/src/App.tsx`; `entity-card:grafana/dashboards`
  and `entity-card:grafana/alerts` enabled under `app.extensions`.
- **Proxy** `/grafana/api` → `${GRAFANA_URL}` with the service-account token
  (`credentials: dangerously-allow-unauthenticated` — local only).
- **Catalog locations** (absolute paths into the stack repo):
  the `observability-onboarding` template + the `payments-api` example component.

## Try it

1. **Sidebar → Catalog → payments-api** → *Overview* tab shows the **Grafana
   Dashboards** card (the `payments-api` RED dashboard, matched by the
   `grafana/tag-selector` annotation) and a **Grafana Alerts** card.
2. **Create… → Onboard a service into the Observability Stack** → the scaffolder
   form. (Publishing needs a `GITHUB_TOKEN` env var with repo access; without it
   the form still renders and you can step through it.)
