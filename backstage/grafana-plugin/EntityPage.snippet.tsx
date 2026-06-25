/*
 * Grafana cards for the component page.
 *
 * These are SNIPPETS to merge into your existing
 *   packages/app/src/components/catalog/EntityPage.tsx
 * (a generated Backstage app already has this file). Don't drop this file in
 * as-is — copy the marked regions into the matching spots.
 */

// 1) Add to the imports at the top of EntityPage.tsx:
// >>> grafana imports start
import {
  EntityGrafanaDashboardsCard,
  EntityGrafanaAlertsCard,
  isDashboardSelectorAvailable,
  isAlertSelectorAvailable,
} from '@backstage-community/plugin-grafana';
// <<< grafana imports end

// 2) Add these cards into `overviewContent` (the Grid for the component
//    "Overview" tab). The EntitySwitch makes a card render only when the entity
//    actually carries the relevant grafana/* annotation, so services that
//    haven't been onboarded just won't show an empty card.
const overviewContent = (
  <Grid container spacing={3} alignItems="stretch">
    {entityWarningContent}
    <Grid item md={6}>
      <EntityAboutCard variant="gridItem" />
    </Grid>

    {/* >>> grafana cards start */}
    <EntitySwitch>
      <EntitySwitch.Case if={isDashboardSelectorAvailable}>
        <Grid item md={6}>
          <EntityGrafanaDashboardsCard />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>

    <EntitySwitch>
      <EntitySwitch.Case if={isAlertSelectorAvailable}>
        <Grid item md={6}>
          <EntityGrafanaAlertsCard />
        </Grid>
      </EntitySwitch.Case>
    </EntitySwitch>
    {/* <<< grafana cards end */}

    <Grid item md={4} xs={12}>
      <EntityLinksCard />
    </Grid>
    {/* ...the rest of your existing overviewContent... */}
  </Grid>
);
