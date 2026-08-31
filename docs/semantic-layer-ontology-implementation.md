# Executive Analyst — Semantic Layer & Ontology (Implementation Summary)

This document describes **what was implemented** in this repo for the Unity Catalog semantic layer, Phase 2 ontology, and Phase 3 Delta knowledge graph. It is a delivery record, not a design manifesto.

**Design / runbooks (how to think about it):**

- [`semantic-layer-ontology-knowledge-graph.md`](semantic-layer-ontology-knowledge-graph.md) — layers and Phases 1–4
- [`ontology-uc-glossary-domains.md`](ontology-uc-glossary-domains.md) — Phase 2 step-by-step runbook
- [`prd.md`](prd.md) — domains, grains, sample questions

**Rule used throughout:** KPI math and grain live in **metric views**. Shared term meaning lives in **glossary YAML + UC tags**. Genie **consumes** both; it is not the system of record. The property graph is for **navigation** only.

---

## Architecture (as built)

```text
┌─────────────────────────────────────────────────────────────────┐
│  Genie space (agent)                                            │
│  thin policy + certified sql_snippets + sample questions           │
│  src/executive_analyst.geniespace.json                          │
└────────────────────────────┬────────────────────────────────────┘
                             │ MEASURE / filters / routing
┌────────────────────────────▼────────────────────────────────────┐
│  Semantic layer — Unity Catalog metric views                    │
│  five metrics_* (+ dim joins, measures, comments)               │
│  src/metric_views/metrics_*.sql                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │ tags / grants / comments
┌────────────────────────────▼────────────────────────────────────┐
│  Ontology lite — glossary + UC tags + OWL TBox (Git)            │
│  glossary.yml + graph.yml → generate_owl.py → exec_analyst.ttl  │
│  glossary.yml → generate_tag_sql.py → tag_metric_views.sql      │
│  grant_metric_views.sql (ACL prep for Genie Ontology)           │
└────────────────────────────┬────────────────────────────────────┘
                             │ materialize (same apply job)
┌────────────────────────────▼────────────────────────────────────┐
│  Phase 3 — Delta property graph (ABox)                          │
│  ontology.kg_nodes / kg_edges (dims + fact key pairs + KPIs)    │
│  Not a Genie data source; query via kg_queries.sql              │
└─────────────────────────────────────────────────────────────────┘
```

| Layer | Job | Implemented home |
| --- | --- | --- |
| **Semantic layer** | One governed definition of measures, dimensions, joins, grain | Five UC **metric views** |
| **Ontology (authored)** | What terms/entities mean and how they differ | `glossary.yml` + UC tags on views/dims |
| **OWL TBox (generated)** | Formal class / object properties / disjointness / asset annotations | `exec_analyst.ttl` (Git-only; not Genie runtime) |
| **Knowledge Store** | Certified agent bindings + short policy | Genie `sql_snippets` + `text_instructions` |
| **Genie Ontology (product)** | Learned context graph | **Not installed** — prep only (Step 6) |
| **Property graph (ABox)** | “How is Plant X connected?” | `{catalog}.ontology.kg_nodes` / `kg_edges` via `materialize_kg.sql` |

---

## Phase 1 — Semantic layer (implemented)

### Five metric views

Applied by the `apply_metric_views` job (`./deploy.sh apply-metrics`). Catalog: `gold_dev` (dev) / `gold` (prod).

| Metric view | Source fact | Grain (tag) | Example measures / filters |
| --- | --- | --- | --- |
| `revenue_analytics.metrics_sales_order` | `fact_sales_order` | order | `total_revenue`, `total_bookings`, `total_discount`, `delivered_order_revenue` |
| `marketing_analytics.metrics_campaign_performance` | `fact_campaign_performance` | campaign_flight | `weighted_roas`, `cost_per_lead`, `total_conversions` |
| `manufacturing_analytics.metrics_production_execution` | `fact_production_execution` | production_row | `average_oee`, `total_downtime`, `oee_below_70` |
| `supply_chain_analytics.metrics_inventory_snapshot` | `fact_inventory_snapshot` | snapshot | `average_days_of_supply`, `high_stockout`, `is_current_snapshot` |
| `supply_chain_analytics.metrics_supplier_quality` | `fact_supplier_quality` | inspection | `ppm`, `copq`, `average_quality_score` |

Views were renamed from legacy `mv_executive_*` to `metrics_<fact without fact_>`. Legacy names are dropped by `drop_legacy_mv_executive.sql` after apply.

### Dimension joins (entity names)

Confirmed in [`src/metric_views/column_map.md`](../src/metric_views/column_map.md) and enabled in each `metrics_*.sql`:

| Domain | Joined dims (name fields) |
| --- | --- |
| Revenue | `dim_dealer` → `dealer_name`, `dim_vehicle_model` → `model_name`, `dim_date` → `order_date` |
| Marketing | `dim_campaign`, `dim_channel`, `dim_customer_segment`, `dim_date` |
| Manufacturing | `dim_plant`, `dim_production_line`, `dim_vehicle_model`, `dim_date`; **no `dim_shift`** — `shift_code` from fact |
| Inventory | `dim_part`, `dim_warehouse`, `dim_date`; `is_current_snapshot` for latest day |
| Supplier quality | `dim_supplier`, `dim_part`, `dim_date` |

### Important KPI contracts encoded in views

- **Revenue** = `SUM(ORDER_AMOUNT)`; **Bookings** = `SUM(BOOKING_AMOUNT)` (separate).
- **ROAS / CPL** = rolled-up / spend-weighted measures — never `AVG(ROAS)` or `AVG(COST_PER_LEAD)`.
- **OEE** stored as **0–100** percent; “below 70%” = `OEE_PCT < 70` / field `oee_below_70`.
- **PPM** = `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6` — never `SUM(PPM_LEVEL)`.
- **Inventory** is point-in-time: filter `is_current_snapshot`; never sum on-hand/valuation across dates.

### Bundle / deploy

| Asset | Role |
| --- | --- |
| `databricks.yml` | Bundle targets `dev` / `prod`, warehouse, catalog, Genie permission group |
| `resources/metric_views_job.yml` | Ordered job: create views → tags → grants → **materialize KG** → grant KG → drop legacy |
| `resources/executive_analyst.genie_space.yml` | Deploys Genie space |
| `deploy.sh` | `validate` \| `deploy` \| `apply-metrics` \| `regen-tags` (tags + OWL) \| `open` \| `destroy` |

---

## Phase 2 — Ontology lite (implemented)

Ontology here means **shared meaning of terms and entities**, not OWL.

### Step status

| Step | Status | What landed in the repo |
| --- | --- | --- |
| **0** Entity substrate | Done | Dim joins + `column_map.md` |
| **1** UC Domains | Skipped | `domain` tag on each metric view instead |
| **2** Glossary | Done (Git) | [`src/ontology/glossary.yml`](../src/ontology/glossary.yml) |
| **3** Wire terms → assets | Done (as code) | UC tags via `tag_metric_views.sql` |
| **4** Genie Knowledge Store | Done | Thin instructions + certified snippets + 15 benchmarks |
| **5** As-code packaging | Done | YAML + generated tags; REST glossary upsert **deferred** (API not GA) |
| **6** Genie Ontology prep | Done as prep | Grants SQL + checklist; product **not** installed |
| **7** OWL | TBox generated | [`exec_analyst.ttl`](../src/ontology/exec_analyst.ttl) from glossary + [`graph.yml`](../src/ontology/graph.yml) via [`generate_owl.py`](../src/ontology/generate_owl.py); not deployed; Protégé review only |

### Glossary (`glossary.yml`)

Git source of truth for definitions, owners, `related` / `not_same_as`, and `links_to` (view measure/field or dim table).

**Measures / concepts:** Revenue, Bookings, Discount, Delivered order, ROAS, CPL, Conversion (marketing), OEE, Downtime, Stockout risk, Days of supply, Inventory turnover, PPM, COPQ.

**Ambiguous (no asset links):** Cost, Efficiency — Genie policy should clarify.

**Entities:** Plant, Production line, Part, Warehouse, Supplier, Dealer, Model, Campaign, Channel, Segment.

Catalog Explorer Glossary Pages Assign remains **optional / deferred** ([`wiring_checklist.md`](../src/ontology/wiring_checklist.md)).

### UC tags (generated)

[`generate_tag_sql.py`](../src/ontology/generate_tag_sql.py) regenerates [`tag_metric_views.sql`](../src/metric_views/tag_metric_views.sql) from `links_to` so tags cannot drift from YAML.

```bash
./deploy.sh regen-tags
# or: python src/ontology/generate_tag_sql.py --check
#     python src/ontology/generate_owl.py --check
```

Tags applied on apply-metrics:

| Tag | Purpose |
| --- | --- |
| `domain` | revenue \| marketing \| manufacturing \| inventory \| supplier_quality |
| `grain` | order \| campaign_flight \| production_row \| snapshot \| inspection |
| `kpi` | `true` on metric views |
| `glossary_source` | `src/ontology/glossary.yml` |
| `glossary_terms` | Comma-separated term ids linked to that view/dim |

### OWL TBox (Step 7 seed)

[`generate_owl.py`](../src/ontology/generate_owl.py) regenerates [`exec_analyst.ttl`](../src/ontology/exec_analyst.ttl) from [`glossary.yml`](../src/ontology/glossary.yml) + [`graph.yml`](../src/ontology/graph.yml) (IRI `https://focaloid.com/ontology/executive-analyst#`, prefix `ea:`). Classes, `skos:related`, `owl:disjointWith`, `ea:realizedBy*` annotations, and **object properties** (`hasLine`, `stockedAt`, …) with `rdfs:domain` / `rdfs:range`. No ABox individuals in Turtle; no Databricks deploy of the TTL. Protégé: open to review types; never save over the file. `pip install -r src/ontology/requirements.txt`.

### Genie Knowledge Store (Step 4)

[`src/executive_analyst.geniespace.json`](../src/executive_analyst.geniespace.json):

- **Data sources:** five `metrics_*` + five facts for drill (legacy `fact_inventory_snapshot_metric_view` **removed**).
- **Policy:** metric views first; never cross-domain JOIN; ask on ambiguous cost/efficiency; INR / Cr / Lakh formatting.
- **Certified filters:** high stockout (+ current snapshot), restock candidates, OEE below 70%, delivered orders.
- **Certified measures:** PPM, average OEE, weighted ROAS, COPQ, total revenue, cost per lead, delivered order revenue.
- **Sample questions:** 15 chips aligned with the benchmark suite.

Eval suite: [`src/ontology/benchmark_questions.md`](../src/ontology/benchmark_questions.md).

### Grants & Genie Ontology prep (Step 6)

[`grant_metric_views.sql`](../src/metric_views/grant_metric_views.sql) grants `SELECT` on the five metric views and ten tagged dims to `genie_space_permission_group` (default `users`).

Operational checklist: [`src/ontology/genie_ontology_prep.md`](../src/ontology/genie_ontology_prep.md) (tags, comments, `SHOW GRANTS`, Table Insights via real Genie usage, enable product Ontology only when workspace preview exists).

---

## Phase 3 — Delta property graph (implemented)

Navigation graph only. KPI math stays in `metrics_*`. **Not** added to the Genie space.

| Asset | Role |
| --- | --- |
| [`graph.yml`](../src/ontology/graph.yml) | Object-property SoR (`rel`, domain/range class ids) |
| [`materialize_kg.sql`](../src/ontology/materialize_kg.sql) | `kg_nodes` + `kg_edges` (schema `{catalog}.ontology` must already exist) |
| [`grant_kg.sql`](../src/ontology/grant_kg.sql) | `GRANT USAGE` / `SELECT` to reader group |
| [`kg_queries.sql`](../src/ontology/kg_queries.sql) | Neighborhood examples (SQL editor; not a job task) |

**Nodes:** Plant, ProductionLine, Model, Dealer, Part, Warehouse, Supplier, Campaign, Channel, Segment — from `dim.*`, with optional KPI properties (OEE, stockout, PPM/COPQ, revenue, weighted ROAS) using aggregations that match metric-view expressions.

**Edges (`rel`):** `hasLine`, `produces`, `soldBy`, `stockedAt` (current snapshot only), `supplies`, `runsOnChannel`, `runsOnSegment` — distinct key pairs from facts.

Job tasks on `apply_metric_views`: `materialize_kg` → `grant_kg` → `tag_metric_views` → `grant_metric_views` → `drop_legacy_mv_executive`. Metric-view `CREATE OR REPLACE` is not in the job unless the KPI YAML changes.

**View relationships:** Protégé on TTL = TBox; SQL on `kg_nodes`/`kg_edges` = ABox.

---

## How to change meaning safely

| Change | Edit | Then |
| --- | --- | --- |
| KPI formula / grain / join | `src/metric_views/metrics_*.sql` | `deploy` + `apply-metrics` |
| Term definition or `links_to` | `src/ontology/glossary.yml` | `regen-tags` (tags SQL + OWL Turtle) → `deploy` → `apply-metrics` |
| Typed edge / object property | `src/ontology/graph.yml` (+ `materialize_kg.sql` if new fact pair) | `regen-tags` → `deploy` → `apply-metrics` |
| Agent policy / certified SQL | `src/executive_analyst.geniespace.json` | `deploy` |
| Reader group for SELECT | `genie_space_permission_group` in `databricks.yml` | `deploy` + `apply-metrics` |

Always prefer a **Git PR** over silent Genie UI edits.

---

## How to verify

1. **Tags:** SQL in `wiring_checklist.md` / `genie_ontology_prep.md` against `gold_dev.information_schema.table_tags`.
2. **Grants:** `SHOW GRANTS ON VIEW gold_dev.…metrics_*`; `SHOW GRANTS ON TABLE gold_dev.ontology.kg_nodes`.
3. **Genie behavior:** run questions in `benchmark_questions.md` (especially traps: cost, efficiency, ROAS avg, conversions ≠ delivered, revenue ≠ bookings, snapshot summing).
4. **Tag/YAML sync:** `python src/ontology/generate_tag_sql.py --check`.
5. **OWL/YAML sync:** `python src/ontology/generate_owl.py --check` (glossary + graph).
6. **KG:** row counts by `node_type` / `rel`; orphan edge check and neighborhood samples in [`kg_queries.sql`](../src/ontology/kg_queries.sql). No Campaign–Order `rel`.

Observed in smoke testing: cross-domain “how is the business doing?” and OEE/plant naming bind correctly; ambiguous **efficiency** may still skip clarification (policy gap, not missing metric-view math).

---

## Explicitly not implemented

- Formal Unity Catalog **Domains** / Glossary Pages REST upsert
- **Genie Ontology** product install (prep only)
- **OntoBricks** / RDF triples / OWL 2 RL reasoning (Delta property graph is the Phase 3 path; OntoBricks still optional later)
- Campaign → Order **bridge** edges (blocked until gold has a bridge table)
- Neo4j sync / Bloom (optional later; Delta remains SoR)
- Prod Genie JSON identifiers switched to catalog `gold` (still `gold_dev.*` in the space file)
- KG tables as Genie data sources

---

## Repo map (ontology + semantics)

| Path | Role |
| --- | --- |
| `src/metric_views/metrics_*.sql` | Semantic layer KPI definitions |
| `src/metric_views/column_map.md` | Confirmed dim keys / name columns |
| `src/metric_views/tag_metric_views.sql` | Generated UC tags |
| `src/metric_views/grant_metric_views.sql` | `GRANT SELECT` for reader group |
| `src/ontology/glossary.yml` | Glossary source of truth |
| `src/ontology/graph.yml` | Object properties for TBox + `kg_edges.rel` |
| `src/ontology/materialize_kg.sql` | Phase 3 `kg_nodes` / `kg_edges` |
| `src/ontology/grant_kg.sql` | KG grants |
| `src/ontology/kg_queries.sql` | Neighborhood SQL examples |
| `src/ontology/generate_tag_sql.py` | Tag SQL generator |
| `src/ontology/generate_owl.py` | OWL Turtle generator (`ea:` / Focaloid IRI) |
| `src/ontology/exec_analyst.ttl` | GENERATED OWL TBox (Git-only; Protégé review) |
| `src/ontology/requirements.txt` | PyYAML, owlready2, rdflib |
| `src/ontology/benchmark_questions.md` | Eval questions |
| `src/ontology/genie_ontology_prep.md` | Step 6 checklist |
| `src/ontology/wiring_checklist.md` | Optional UI Assign (deferred) |
| `src/executive_analyst.geniespace.json` | Genie Knowledge Store |
| `docs/ontology-uc-glossary-domains.md` | Phase 2 runbook |
| This doc | Implementation summary of what was built |

---

*Dev first on `gold_dev`. Promote metric views, tags, grants, KG tables, and Genie to prod when catalog ownership and identifiers are ready.*
