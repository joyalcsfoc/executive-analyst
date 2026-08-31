# Executive Analyst — Databricks Asset Bundle

Deployable [Declarative Automation Bundle](https://docs.databricks.com/aws/en/dev-tools/bundles/) (formerly "Databricks Asset Bundle") that defines:

1. **Five Unity Catalog metric views** (semantic layer) applied by a warehouse job
2. The **Executive Analyst** Genie space as code, based on [`docs/prd.md`](docs/prd.md)

Semantic-layer design: [`docs/semantic-layer-ontology-knowledge-graph.md`](docs/semantic-layer-ontology-knowledge-graph.md). **What was built:** [`docs/semantic-layer-ontology-implementation.md`](docs/semantic-layer-ontology-implementation.md). Ontology runbook + assets: [`docs/ontology-uc-glossary-domains.md`](docs/ontology-uc-glossary-domains.md) · [`src/ontology/glossary.yml`](src/ontology/glossary.yml) · [`src/ontology/benchmark_questions.md`](src/ontology/benchmark_questions.md) · [`src/ontology/genie_ontology_prep.md`](src/ontology/genie_ontology_prep.md).

Genie space bundle support requires **Databricks CLI ≥ 1.3.0** and the **`direct` deployment engine** (already set in `databricks.yml`).

## What this deploys

| Resource | Path | Role |
| --- | --- | --- |
| `apply_metric_views` job | [`resources/metric_views_job.yml`](resources/metric_views_job.yml) | Tags, grants, Phase 3 `ontology.kg_nodes` / `kg_edges`, drop legacy `mv_executive_*` (does not recreate `metrics_*` views) |
| `validate_metric_views` job | [`resources/validate_metric_views_job.yml`](resources/validate_metric_views_job.yml) | Read-only KPI-formula, dim-uniqueness, and fan-out assertions on the five `metrics_*` views ([`src/tests/`](src/tests/)) |
| Metric view SQL | [`src/metric_views/`](src/metric_views/) | YAML 1.1 definitions + [`tag_metric_views.sql`](src/metric_views/tag_metric_views.sql) + [`grant_metric_views.sql`](src/metric_views/grant_metric_views.sql) |
| Glossary + graph (Git) | [`src/ontology/glossary.yml`](src/ontology/glossary.yml) · [`graph.yml`](src/ontology/graph.yml) | Terms + object properties; `./deploy.sh regen-tags` refreshes tags SQL + OWL; UI Assign deferred ([`wiring_checklist.md`](src/ontology/wiring_checklist.md)) |
| Knowledge graph (Delta) | [`src/ontology/materialize_kg.sql`](src/ontology/materialize_kg.sql) | `{catalog}.ontology.kg_nodes` / `kg_edges` — instance graph for navigation (not a Genie source) |
| Genie space | [`resources/executive_analyst.genie_space.yml`](resources/executive_analyst.genie_space.yml) + [`src/executive_analyst.geniespace.json`](src/executive_analyst.geniespace.json) | Thin agent: metric views for KPIs, facts for drill |

### Metric views (catalog = `gold_dev` in dev, `gold` in prod)

| View | Source fact |
| --- | --- |
| `{catalog}.revenue_analytics.metrics_sales_order` | `fact_sales_order` |
| `{catalog}.marketing_analytics.metrics_campaign_performance` | `fact_campaign_performance` |
| `{catalog}.manufacturing_analytics.metrics_production_execution` | `fact_production_execution` |
| `{catalog}.supply_chain_analytics.metrics_inventory_snapshot` | `fact_inventory_snapshot` |
| `{catalog}.supply_chain_analytics.metrics_supplier_quality` | `fact_supplier_quality` |

KPI contract for inventory is `metrics_inventory_snapshot` only (legacy `fact_inventory_snapshot_metric_view` is not a Genie data source).

Dim joins are enabled on the five `metrics_*` views (confirmed against `gold_dev` — see [`src/metric_views/column_map.md`](src/metric_views/column_map.md)). Re-run [`discover_dims.sql`](src/metric_views/discover_dims.sql) if schemas change.

## Deploy order (important)

Genie validates that data sources exist at creation/update time. **Create metric views before the Genie space can reference them.**

```bash
# authenticate once
databricks auth login --host https://<your-workspace-host>

# 1) Deploy the job (and Genie if views already exist)
./deploy.sh deploy --target dev --profile data --warehouse-id <your-warehouse-id>

# 2) Refresh tags, grants, and ontology.kg_* tables (does not recreate metrics_* views)
./deploy.sh apply-metrics --target dev --profile data

# 3) Re-deploy so Genie picks up the metric-view identifiers (if step 1 failed or was facts-only)
./deploy.sh deploy --target dev --profile data --warehouse-id <your-warehouse-id>

# 4) Read-only KPI-formula + dim-uniqueness assertions (safe to run anytime)
./deploy.sh test-metrics --target dev --profile data

./deploy.sh open --target dev --profile data
```

Warehouse identity needs:

- `SELECT` on the five gold fact tables and `dim.*` used by joins
- `CREATE` / `CREATE VIEW` on the domain schemas (`revenue_analytics`, `marketing_analytics`, `manufacturing_analytics`, `supply_chain_analytics`)
- Write access on `{catalog}.ontology` to create/replace `kg_nodes` / `kg_edges` (schema must already exist)

`apply-metrics` also grants `SELECT` on the five `metrics_*` views, linked dims, and `ontology.kg_*` to `genie_space_permission_group` (default `users`). See [`src/ontology/genie_ontology_prep.md`](src/ontology/genie_ontology_prep.md).

### Knowledge graph (Phase 3)

| Table | Role |
| --- | --- |
| `{catalog}.ontology.kg_nodes` | Entity instances (Plant, Part, …) + latest KPI properties |
| `{catalog}.ontology.kg_edges` | Typed edges (`hasLine`, `stockedAt`, `supplies`, …) from fact key pairs |

- **TBox (types):** Protégé on [`src/ontology/exec_analyst.ttl`](src/ontology/exec_analyst.ttl) (classes + object properties from `glossary.yml` + `graph.yml`)
- **ABox (instances):** SQL against `kg_nodes` / `kg_edges` — examples in [`src/ontology/kg_queries.sql`](src/ontology/kg_queries.sql)
- Not added to the Genie space; KPI math stays in `metrics_*`. No Campaign→Order edges until gold has a bridge table.

Override catalog with `--gold-catalog` or `--var gold_catalog=...`. Dev defaults to `gold_dev`; prod target defaults to `gold`.

### SQL test suite (KPI traps + dim-join assumptions)

The `validate_metric_views` job ([`resources/validate_metric_views_job.yml`](resources/validate_metric_views_job.yml))
runs four read-only SQL tasks against the five `metrics_*` views:

- `assert_dim_uniqueness` — the `rely: { at_most_one_match: true }` assumption on every dim join actually holds (a violated assumption silently fans out joins and corrupts every KPI on that view).
- `assert_view_row_counts` — each metric view's row count matches its source fact (fan-out canary).
- `assert_kpi_formulas` — the documented traps hold: weighted ROAS ≠ `AVG(ROAS)`, CPL ≠ `AVG(COST_PER_LEAD)`, PPM is a ratio of sums not `SUM(PPM_LEVEL)`, `discount_percent` stays 0–100, revenue is never conflated with bookings, OEE stays 0–100.
- `assert_snapshot_grain` — `is_current_snapshot` resolves to exactly one date, and stockout flags match `STOCKOUT_RISK`.

Each SQL file in [`src/tests/`](src/tests/) has a diagnostic statement (paste into a
SQL editor; 0 rows = pass) and a gate statement (`raise_error` on any violation,
which fails the task). Run it with:

```bash
./deploy.sh test-metrics --target dev
```

This is a SQL-correctness check, independent of Genie — it catches a regressed
measure formula even if no one has asked Genie the matching question yet. The
Genie-facing companion eval is [`src/ontology/benchmark_questions.md`](src/ontology/benchmark_questions.md);
see [`src/tests/README.md`](src/tests/README.md) for how the two map to each other.

### Clustering (Liquid Clustering) on gold fact tables

No clustering or partitioning exists on the gold fact tables today. As they grow,
Genie query latency will degrade because every certified measure/filter hits the
same handful of join/date keys with no physical layout support.

[`src/clustering/discover_clustering_candidates.sql`](src/clustering/discover_clustering_candidates.sql)
is read-only and safe to run anytime — it captures baseline size and key
cardinality. [`src/clustering/clustering_candidates.md`](src/clustering/clustering_candidates.md)
holds the proposed `CLUSTER BY` keys per table and a sign-off checklist.
[`src/clustering/cluster_gold_facts.sql`](src/clustering/cluster_gold_facts.sql) has
the drafted `ALTER TABLE ... CLUSTER BY` statements — **it is not wired into any job
or `deploy.sh` action, and must not be run without the gold-table-owning team's
sign-off**, since these tables are created and owned upstream, outside this bundle.

## Repo layout

```
databricks.yml                                # bundle root: engine, variables (warehouse_id, gold_catalog, grant group), targets
resources/executive_analyst.genie_space.yml   # genie_space resource
resources/metric_views_job.yml                # apply_metric_views (+ tag + grant + KG + drop legacy)
resources/validate_metric_views_job.yml       # validate_metric_views (read-only SQL test suite)
src/executive_analyst.geniespace.json         # Genie: metric views + facts, thin instructions
src/metric_views/metrics_*.sql                # CREATE OR REPLACE VIEW WITH METRICS
src/metric_views/tag_metric_views.sql         # UC tags (GENERATED from glossary.yml)
src/metric_views/grant_metric_views.sql       # GRANT SELECT on metrics_* + dims (Step 6)
src/metric_views/drop_legacy_mv_executive.sql # DROP legacy mv_executive_* after rename
src/metric_views/column_map.md                # confirmed dim keys and joins
src/tests/assert_*.sql                        # KPI-formula + dim-uniqueness + fan-out assertions
src/tests/README.md                           # test pattern + benchmark_questions.md cross-reference
src/clustering/discover_clustering_candidates.sql # read-only size/cardinality discovery
src/clustering/clustering_candidates.md       # proposed CLUSTER BY keys + sign-off checklist
src/clustering/cluster_gold_facts.sql         # drafted ALTER TABLE ... CLUSTER BY (owner sign-off required)
src/ontology/glossary.yml                     # glossary source of truth (terms)
src/ontology/graph.yml                        # object properties (hasLine, stockedAt, …)
src/ontology/materialize_kg.sql               # CREATE ontology.kg_nodes / kg_edges
src/ontology/grant_kg.sql                     # GRANT SELECT on KG tables
src/ontology/kg_queries.sql                   # neighborhood SQL examples (not a job task)
src/ontology/generate_tag_sql.py              # regenerates tag_metric_views.sql from links_to
src/ontology/generate_owl.py                  # regenerates exec_analyst.ttl from glossary + graph
src/ontology/exec_analyst.ttl                 # GENERATED OWL Turtle (Git-only; Protégé review)
src/ontology/requirements.txt                 # PyYAML, owlready2, rdflib for ontology compilers
src/ontology/wiring_checklist.md              # optional Catalog Explorer Assign (deferred)
src/ontology/benchmark_questions.md           # Genie Knowledge Store eval suite (Step 4)
src/ontology/genie_ontology_prep.md           # Step 6 readiness (grants, popularity, preview)
docs/prd.md                                   # domain PRD
docs/semantic-layer-ontology-knowledge-graph.md
docs/ontology-uc-glossary-domains.md          # Phase 2 runbook + Phase 3 Delta KG
deploy.sh                                     # validate | deploy | apply-metrics | regen-tags | open | destroy
```

## Updating definitions

**Metric views:** edit `src/metric_views/metrics_*.sql`, then run those `CREATE OR REPLACE` statements on the warehouse (the apply job no longer recreates views). Then:

```bash
./deploy.sh deploy --target dev
./deploy.sh apply-metrics --target dev   # tags + grants + KG
```

**Glossary terms / links or graph object properties:** edit `src/ontology/glossary.yml` and/or `src/ontology/graph.yml`, then:

```bash
./deploy.sh regen-tags                   # refresh tag_metric_views.sql + exec_analyst.ttl
./deploy.sh deploy --target dev
./deploy.sh apply-metrics --target dev   # apply UC tags + grants + refresh kg_*
```

OWL Turtle (`src/ontology/exec_analyst.ttl`) is Git-only — not deployed to Databricks. Open it in Protégé to review **types** (classes + object properties); never save over the generated file. Instance relationships live in `ontology.kg_nodes` / `kg_edges` — query via [`kg_queries.sql`](src/ontology/kg_queries.sql). Dependencies: `pip install -r src/ontology/requirements.txt`.

**Genie space:** edit `src/executive_analyst.geniespace.json`, then `./deploy.sh deploy`. Genie JSON identifiers stay on `gold_dev.*` until you deliberately switch them for prod. After Genie changes, seed Table Insights by running [`benchmark_questions.md`](src/ontology/benchmark_questions.md).

To pull a live Genie space:

```bash
databricks bundle generate genie-space --existing-id <space-id>
```

## Dimension joins

Joins and name fields live in [`src/metric_views/metrics_*.sql`](src/metric_views/). Confirmed map: [`column_map.md`](src/metric_views/column_map.md). After schema changes:

1. Re-run [`discover_dims.sql`](src/metric_views/discover_dims.sql) against the warehouse.
2. Update `column_map.md` and the join blocks in the SQL files.
3. `./deploy.sh deploy --target dev` then `./deploy.sh apply-metrics --target dev`.

## Before you deploy

Confirm `targets.<target>.workspace.host` and `variables.warehouse_id` point at a workspace that has the gold catalog. Deploying Genie against missing tables/views fails with catalog or table not found / permission errors.

For production, use `--target prod` (no `[dev]` name prefix). Update `run_as` to a service principal when ready.
