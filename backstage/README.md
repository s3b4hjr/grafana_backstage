# Backstage integration

Two pieces that make this observability stack self-service from a Backstage
developer portal:

1. **A Software Template** (`templates/observability-onboarding/`) — a "golden
   path" that onboards a service: scaffolds its `catalog-info.yaml` + TechDocs and
   opens a PR on this repo adding a Prometheus scrape target.
2. **Grafana plugin wiring** (`grafana-plugin/`) — config + UI snippets so each
   service page in the portal shows its Grafana **dashboards** and **alerts**.

> These files don't run inside the Docker Compose stack. They configure a
> *separate* Backstage app (`npx @backstage/create-app@latest`). They live here so
> the onboarding contract sits next to the stack it onboards into.

```
backstage/
├── templates/observability-onboarding/
│   ├── template.yaml                       # the Scaffolder template (the form + steps)
│   ├── skeleton/                           # rendered into the NEW service repo
│   │   ├── catalog-info.yaml               #   + grafana/* annotations + techdocs-ref
│   │   ├── mkdocs.yml
│   │   └── docs/index.md
│   └── prometheus-pr/                      # committed onto THIS repo via a PR
│       └── config/prometheus/targets/${{ values.name }}.yml
├── grafana-plugin/
│   ├── app-config.grafana.yaml             # proxy + grafana settings to merge
│   └── EntityPage.snippet.tsx              # cards to add to EntityPage.tsx
└── examples/payments-api/                  # what the template renders for a real service
    ├── catalog-info.yaml
    └── prometheus-target.payments-api.yml
```

---

## Part 1 — The onboarding Software Template

### Register it in Backstage

Point your Backstage `app-config.yaml` at the template (raw URL on GitHub):

```yaml
catalog:
  locations:
    - type: url
      target: https://github.com/s3b4hjr/grafana/blob/main/backstage/templates/observability-onboarding/template.yaml
      rules:
        - allow: [Template]
```

It then appears under **Create… → Onboard a service into the Observability Stack**.

### What it does when run

The developer fills a 3-step form (service name/owner, metrics endpoint, repos).
Then the steps run in order:

| # | Step                  | Action                          | Result |
|---|-----------------------|---------------------------------|--------|
| 1 | Render service files  | `fetch:template` → `./service`  | `catalog-info.yaml` + mkdocs docs, with values substituted |
| 2 | Publish service repo  | `publish:github`                | Creates the service's GitHub repo |
| 3 | Register in catalog   | `catalog:register`              | Service shows up in the portal |
| 4 | Render Prom target    | `fetch:template` → `./prometheus-pr` | A repo-shaped subtree containing `config/prometheus/targets/<name>.yml` |
| 5 | Open target PR        | `publish:github:pull-request`   | PR on **this** repo adding that target file |

Why a PR instead of editing files directly? It keeps the stack **GitOps** — the
metrics target is reviewed and version-controlled, exactly matching this repo's
rule: *"do NOT edit `prometheus.yml`; drop the app's endpoint in
`config/prometheus/targets/*.yml`."* After the PR merges, Prometheus' `applications`
`file_sd` job reloads it in ~30s — no restart.

Logs and traces need **nothing** from the template: Alloy already tails every
container's logs, and traces just need the app to export OTLP to the Alloy gateway
(see the stack's `examples/otel.env`).

---

## Part 2 — Grafana dashboards & alerts on each service page

Plugin: [`@backstage-community/plugin-grafana`](https://github.com/backstage/community-plugins/tree/main/workspaces/grafana).

### 1. Install

```bash
cd packages/app && yarn add @backstage-community/plugin-grafana
```

### 2. Create a Grafana token (so the backend can read the API)

In Grafana: **Administration → Service accounts → Add service account** (role
*Viewer*) → **Add token**. Then expose it to the Backstage backend:

```bash
export GRAFANA_URL=http://localhost:3000     # this stack's Grafana (GRAFANA_PORT in .env)
export GRAFANA_TOKEN=glsa_xxxxxxxxxxxxxxxx
```

### 3. Config + UI

- Merge `grafana-plugin/app-config.grafana.yaml` into your `app-config.yaml`
  (proxy endpoint `/grafana/api` + `grafana.domain` + `unifiedAlerting: true` —
  this stack uses Grafana **unified** alerting, so that flag matters).
- Merge the marked regions of `grafana-plugin/EntityPage.snippet.tsx` into
  `packages/app/src/components/catalog/EntityPage.tsx`.

### How a service is matched to its dashboards/alerts

Via the annotations the template writes into `catalog-info.yaml`:

| Annotation                     | Effect |
|--------------------------------|--------|
| `grafana/tag-selector`         | Dashboards card lists Grafana dashboards carrying this **tag**. |
| `grafana/alert-label-selector` | Alerts card lists alerts whose **labels** match (e.g. `app=<name>`). |

So tag your service dashboards with the service name, and the Prometheus target
(which stamps `app=<name>` on every series) makes alert label-matching line up.

---

## End-to-end: onboarding `payments-api`

Inputs the developer types: `name=payments-api`, `owner=team-payments`,
`metricsHost=host.docker.internal`, `metricsPort=8000`, `path=/metrics`, `env=prod`.

1. **Scaffolder runs.** It publishes the `payments-api` service repo (with the
   `catalog-info.yaml` + docs shown in [`examples/payments-api/`](examples/payments-api/))
   and opens a PR on this repo adding
   [`config/prometheus/targets/payments-api.yml`](examples/payments-api/prometheus-target.payments-api.yml):

   ```yaml
   - targets: ['host.docker.internal:8000']
     labels: { app: payments-api, env: prod, __metrics_path__: /metrics }
   ```

2. **PR merges.** Within ~30s Prometheus picks up the target — confirm at
   `http://localhost:9090/targets` (it shows `app="payments-api"` as **UP**), or:

   ```bash
   curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.app=="payments-api")'
   ```

3. **In the portal.** Open the `payments-api` component page. The **TechDocs** tab
   renders its docs; the **Overview** tab shows the **Grafana dashboards** card
   (everything tagged `payments-api`) and the **Grafana alerts** card (alerts
   labeled `app=payments-api`) — without leaving Backstage.

4. **Logs & traces.** Logs are already in Loki (Alloy). Add `examples/otel.env` to
   the service's environment and traces flow to Tempo via Alloy. Because the repo's
   datasources pre-wire trace↔logs↔metrics correlation, you can pivot across all
   three from any of those panels.

That's the full loop: **one form → a reviewable PR → a service that's scraped,
logged, traced, documented, and visible in the portal.**
