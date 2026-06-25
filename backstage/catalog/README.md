# Catalog organization

How this portal is organized and how new applications + their docs get added —
at one app or at a hundred.

## The model

Backstage is **catalog-as-code**: each thing is an *entity* described by YAML.
The recommended hierarchy:

```
Domain            a business area            (e.g. payments)
  └─ System       a set of related things    (e.g. payments-platform)
       ├─ Component   a service/lib/website  (e.g. payments-api)   ← owns code + docs
       ├─ API         an interface           (e.g. payments-api-openapi)
       └─ Resource    infra (db, bucket, …)
```

Plus the org model — **Group** (team) and **User** — which everything references
via `spec.owner`. Ownership is what powers "owned by my team", who-to-page, etc.

This repo seeds that model in `backstage/catalog/`:

| File | Entities |
|------|----------|
| [`org.yaml`](org.yaml)         | Groups `platform`, `team-payments` |
| [`systems.yaml`](systems.yaml) | Domain `payments` → System `payments-platform` |
| [`all.yaml`](all.yaml)         | a `Location` that aggregates the above + the example service + the template |

`app-config.yaml` registers **one** location (`all.yaml`); it fans out to the rest.

## How a new application gets added — 3 ways

### 1. Register a single repo (one-off)
The app keeps its own `catalog-info.yaml` at its repo root. Then either:
- **UI:** *Create… → Register Existing Component* → paste the repo's `catalog-info.yaml` URL, or
- **config:** add a `type: url` entry under `catalog.locations`.

Best for a handful of repos.

### 2. GitHub discovery (the scale path) ⭐
Backstage scans an org and auto-registers every repo containing a
`catalog-info.yaml` — zero per-app config. Enable it (commented block in
`app-config.yaml` under `catalog.providers`):
```bash
yarn --cwd packages/backend add @backstage/plugin-catalog-backend-module-github
# add the module in packages/backend/src/index.ts, set GITHUB_TOKEN, then:
```
```yaml
catalog:
  providers:
    github:
      myOrg:
        organization: '<your-org>'
        catalogPath: '/catalog-info.yaml'
        schedule: { frequency: { minutes: 30 }, timeout: { minutes: 3 } }
```
This is the right answer once you have more than a few repos.

### 3. The golden-path template (recommended for *new* apps) ⭐⭐
`Create… → Onboard a service into the Observability Stack` scaffolds the repo
**already organized**: a `catalog-info.yaml` with `owner`, `system`, TechDocs and
the Grafana annotations, an `mkdocs.yml` + `docs/`, and it auto-registers the
result + opens the Prometheus-target PR. Nobody hand-writes descriptors → every
service is consistent from day one. See
[`../templates/observability-onboarding/`](../templates/observability-onboarding/).

## Documentation (TechDocs) — docs-as-code

Docs live **in the app's repo**, next to the code:
```
my-service/
├─ catalog-info.yaml      # annotations: backstage.io/techdocs-ref: dir:.
├─ mkdocs.yml             # site_name + nav
└─ docs/
   ├─ index.md
   └─ runbook.md
```
The `backstage.io/techdocs-ref: dir:.` annotation tells Backstage to build the
mkdocs site from this repo. In dev the build runs in Docker (`spotify/techdocs`);
for production, build in CI and serve from object storage (S3/GCS) by switching
`techdocs.builder` to `external`. See [`../examples/payments-api/`](../examples/payments-api/)
for a complete, working example (Component + API + TechDocs).

## Best-practice summary

- **Descriptors live with the code** — never maintain a central pile of YAML.
- **Don't hand-register at scale** — use discovery (#2) or the template (#3).
- **Always set `owner` and `system`** so the graph stays navigable.
- **Docs-as-code** — `mkdocs.yml` + `docs/` in every repo; the template seeds it.
- **One bootstrap location** seeds shared org/domain/system entities (this dir).

## Add a new team / system / service by hand

```yaml
# org.yaml — a new team
kind: Group
metadata: { name: team-checkout }
spec: { type: team, children: [], members: [] }
---
# systems.yaml — a new system
kind: System
metadata: { name: checkout-platform }
spec: { owner: team-checkout, domain: payments }
```
Then point new components at it with `spec: { owner: team-checkout, system: checkout-platform }`.
