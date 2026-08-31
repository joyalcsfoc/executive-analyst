# Executive Analyst — Semantic Layer, Ontology & Knowledge Graph (Production)

This document describes how to add a **production-grade semantic layer, ontology, and knowledge graph** for the Executive Analyst Genie agent, plus related platform work that belongs with those layers.

Today, KPI meaning lives mainly in `src/executive_analyst.geniespace.json`: column synonyms, SQL measures (`weighted_roas`, `total_revenue`), filters, and a long instruction block. That works for a single agent. It does **not** give one KPI definition for dashboards, SQL, alerts, and other agents.

The PRD (`docs/prd.md`) already notes: no dimension names in the space, no safe fact-to-fact joins, and a planned Genie → Neo4j notebook.

**Rule:** put semantics, ontology, and graph meaning **in Unity Catalog first**. Genie should consume them — not be the system of record.

---

## How the three layers fit together

| Layer | Job | Production home on Databricks |
| --- | --- | --- |
| **Semantic layer** | One governed definition of measures, dimensions, joins, grain, and formats | **Unity Catalog Metric Views** (Business Semantics) |
| **Ontology** | Shared meaning of *entities* (Plant, Part, Dealer, Campaign) and how they relate | **UC Glossary + Domains** (authored) + **Genie Ontology** (learned; gated preview as of mid-2026) |
| **Knowledge graph** | Queryable graph of those entities, relationships, and facts | **Genie Knowledge Store** (expressions / certified answers) and/or a **materialized graph** (OntoBricks / Delta + Lakebase / Neo4j) |

- **Metric Views** answer: “what is revenue this quarter?”
- **Ontology / KG** answer: “which plants, parts, and suppliers are connected, and what does Plant mean?”

Do not put KPI math only in Genie instructions. Encode logic in metric views; keep Genie text short.

---

## 1. Semantic layer (do this first)

Unity Catalog **Metric Views** are the production semantic layer: measures and dimensions are defined once, compiled deterministically, governed with UC permissions and lineage, and reused by Genie, AI/BI Dashboards, notebooks, SQL, and alerts.

References:

- [Unity Catalog metric views](https://docs.databricks.com/aws/en/uc-semantics/metric-views/)
- [Curate an effective Genie Agent](https://docs.databricks.com/aws/en/genie/best-practices)
- [Unity Catalog Business Semantics GA](https://www.databricks.com/blog/redefining-semantics-data-layer-future-bi-and-ai)

### Design for this agent

Keep **one metric view per domain** (same grains as the PRD). Do **not** merge all five facts into one view — they still cannot be joined safely.

| Metric view | Source fact | Join dims (`gold_dev.dim.*` / prod `gold.dim.*`) | Example measures |
| --- | --- | --- | --- |
| `metrics_sales_order` | `fact_sales_order` | dealer, model, date | `total_revenue` = `SUM(ORDER_AMOUNT)`; `total_discount`; `total_bookings` |
| `metrics_campaign_performance` | `fact_campaign_performance` | campaign, channel, segment, date | `weighted_roas`; `cost_per_lead`; never `AVG(ROAS)` |
| `metrics_production_execution` | `fact_production_execution` | plant, line, shift, date | `avg_oee`; `total_downtime`; OEE as 0–1, display as % |
| `metrics_inventory_snapshot` | `fact_inventory_snapshot` | part, warehouse, date | Point-in-time: latest snapshot; **never sum** `QTY_ON_HAND` across dates |
| `metrics_supplier_quality` | `fact_supplier_quality` | supplier, part, date | `copq`; PPM = `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6` |

The space already references `gold_dev.supply_chain_analytics.fact_inventory_snapshot_metric_view`. Treat that as a prototype: expand with **joins, dimensions, agent metadata**, and add the other domains.

### What a production metric view includes

- **Source + joins** (star / snowflake) so Genie can say “Plant A”, not `PLANT_KEY = 1042`.
- **Measures** with correct aggregation (weighted ROAS, CPL, PPM belong here, not only in Genie JSON).
- **Dimensions** (plant name, model, dealer, channel, status, stockout band).
- **Filters** (`high_stockout`, `oee_below_70`, `delivered_orders`).
- **Agent metadata**: display names, synonyms, number formats (INR, %, 0–1 OEE).
- **Unity Catalog comments** on the metric view and columns (Genie reads UC comments, not just `.geniespace.json`).

YAML-style sketch (grain and join keys must match gold tables):

```yaml
version: 1.1
source: gold.revenue_analytics.fact_sales_order
joins:
  - name: dim_dealer
    source: gold.dim.dim_dealer
    on: source.DEALER_KEY = dim_dealer.DEALER_KEY
  - name: dim_date
    source: gold.dim.dim_date
    on: source.ORDER_DATE_KEY = dim_date.DATE_KEY

dimensions:
  - name: dealer_name
    expr: dim_dealer.DEALER_NAME
  - name: order_status
    expr: source.STATUS

measures:
  - name: total_revenue
    expr: SUM(source.ORDER_AMOUNT)
    comment: Default revenue. INR.
```

Author in Catalog Explorer, then **check YAML/SQL into the Databricks Asset Bundle** so `dev` vs `prod` is Git-promoted, same as the Genie space.

### Production extras on metric views

- **Materialization:** pre-aggregate heavy measures (OEE by plant/day, inventory latest snapshot) so exec questions stay interactive.
- **Catalog split:** `gold_dev` for sandbox; production metric views on **`gold`** (or the real prod catalog). The Genie `prod` target in `databricks.yml` must point at those identifiers.
- **Genie space change:** add the five metric views as primary data sources; keep raw facts only if row-level drill is still required. Stay under the **~30 object** Genie limit by collapsing facts + dims into views.

Pattern: domain Genie spaces on metric views, not raw tables. See [Mercedes-Benz Korea — Talk to Data](https://www.databricks.com/blog/unlocking-semantics-ai-how-mercedes-benz-korea-built-trusted-talk-to-data-scale).

---

## 2. Ontology (entities and meaning)

Do not start with OWL. Start with **authored Unity Catalog semantics**, then optionally a formal ontology.

### A. Unity Catalog Glossary + Domains (build now)

**Runbook (term catalog, domains, tags, certified SQL):** [`ontology-uc-glossary-domains.md`](ontology-uc-glossary-domains.md).

This is the **user-defined** half of the Genie Ontology stack ([What’s new with Unity Catalog at DAIS 2026](https://www.databricks.com/blog/whats-new-unity-catalog-data-ai-summit-2026)):

- **Domains:** Revenue, Marketing, Manufacturing, Inventory, Supplier Quality (PRD §4).
- **Glossary terms:** Revenue vs Bookings, OEE, ROAS, CPL, PPM, Days of Supply, Stockout Risk, COPQ, STATUS pipeline.
- **Links:** term → metric view measure / dimension; term ↔ related terms (“efficiency” → OEE *or* turnover).
- **Ownership:** finance owns Revenue; ops owns OEE. Suggestions/comments so definitions do not drift.

This is what stops Genie from treating `CONVERSIONS` as `DELIVERED` orders — that is an ontology distinction, not a SQL trick.

### B. Databricks Genie Ontology (prepare, don’t wait)

Announced June 2026; **gated preview**, not generally available. It is a **learned context graph**: tables, queries, dashboards, column popularity, glossary, metric views, permissions.

Prepare by:

1. Putting real semantics in Metric Views + Glossary (not only Genie text).
2. Using UC tags, descriptions, and **column popularity** (Table Insights).
3. Keeping permissions correct — the ontology is ACL-aware.

Prep write-up: [Genie Ontology: how to prepare](https://hiflylabs.com/blog/2026/7/29/how-to-prepare-for-databricks-genie-ontology).

### C. Formal ontology (OWL) — TBox seeded; reasoning later

**Seed in Git:** [`src/ontology/exec_analyst.ttl`](../src/ontology/exec_analyst.ttl), generated from [`glossary.yml`](../src/ontology/glossary.yml) + [`graph.yml`](../src/ontology/graph.yml) by [`generate_owl.py`](../src/ontology/generate_owl.py) (`ea:` / `https://focaloid.com/ontology/executive-analyst#`). Edit YAML, run `./deploy.sh regen-tags`; open Turtle in Protégé for review only. Instance graph is Delta `kg_nodes` / `kg_edges`, not Turtle individuals.

If you need inferences such as “this part is critical because it is on a high-OEE line **and** HIGH stockout **and** supplied by a high-PPM vendor”, that is still **OntoBricks / OWL reasoning**, not a metric view.

Databricks Labs **[OntoBricks](https://github.com/databrickslabs/ontobricks/)**:

1. Import UC metadata.
2. Use / extend the generated ontology (entities: Plant, Line, Part, Warehouse, Supplier, Campaign, Dealer, Order).
3. Map to tables (R2RML-style).
4. Materialize triples (Delta / Lakebase).
5. Reason (OWL 2 RL, SWRL, SHACL) and query (GraphQL).

For automotive, seed from manufacturing ontologies (for example IOF) rather than inventing Part and Plant from scratch.

**Entity sketch for this domain:**

```text
Plant --hasLine--> ProductionLine --runs--> ProductionOrder
Part --stockedAt--> Warehouse --hasSnapshot--> InventoryState
Supplier --supplies--> Part --inspectedIn--> QualityInspection
Campaign --generates--> Lead --(bridge, later)--> SalesOrder
Dealer --places--> SalesOrder --for--> Model
```

Cross-domain edges (Campaign → Order) need **bridge/aggregate tables** in gold — already listed in PRD §8.2. The graph cannot invent a join the lakehouse does not have.

---

## 3. Knowledge graph (two products)

### A. Genie Knowledge Store (required for production Genie)

This is Databricks **agent knowledge**, not a Neo4j graph:

- SQL **expressions** (promote important measures/filters from the Genie JSON into **metric views**; keep a few as Genie examples).
- **Example / trusted SQL** for the 8 PRD sample questions plus 10–20 more benchmarks.
- **Certified answers** for questions that must not drift (“OEE below 70%” = `OEE_PCT < 0.70`).
- Short **text instructions** only for policy (INR, Cr/Lakh, ask when “cost” is ambiguous).

Production loop: 10–20 benchmark questions → measure accuracy → fix data/metrics, not prompt sprawl. See [How to Build Production-Ready Genie Spaces](https://www.databricks.com/blog/how-build-production-ready-genie-spaces-and-build-trust-along-way).

### B. Materialized knowledge graph (Phase 3 — Delta property graph, implemented)

The PRD’s **Genie to Neo4j** notebook (parse generated SQL → graph) is a **demo pattern**. It is weak in production: the graph tracks *what Genie said*, not a governed enterprise model, and it will duplicate or contradict Metric Views.

| Approach | Status in this repo |
| --- | --- |
| **Property graph tables in Delta** | **Implemented** — `{catalog}.ontology.kg_nodes` / `kg_edges` via [`materialize_kg.sql`](../src/ontology/materialize_kg.sql) on `apply_metric_views` |
| **OntoBricks / Delta triples + Lakebase** | Not built; optional later for OWL reasoning |
| **Neo4j / other GDBMS** | Not built; optional viewer load from Delta SoR |

**What is materialized:**

- **Nodes:** Plant, ProductionLine, Part, Warehouse, Supplier, Dealer, Model, Campaign, Channel, Segment
- **Edges:** `hasLine`, `produces`, `soldBy`, `stockedAt`, `supplies`, `runsOnChannel`, `runsOnSegment` (aligned with [`graph.yml`](../src/ontology/graph.yml))
- **Properties:** average OEE / downtime, stockout / DOS, PPM / COPQ, dealer revenue, campaign weighted ROAS — aggregations match metric-view expressions

Neighborhood SQL: [`kg_queries.sql`](../src/ontology/kg_queries.sql). Protégé on TTL = TBox; Delta tables = ABox. Do not add `kg_*` to Genie sources.

---

## 4. Related production work

These sit next to semantics / ontology / KG. Skipping them is why “we added a semantic layer” still fails in production.

1. **Dimension enrichment** — add `gold_dev.dim.*` (then prod `gold.dim.*`) via metric-view joins. Highest ROI vs any graph tool.
2. **Time intelligence** — date dimension with fiscal calendar, `is_current_snapshot` for inventory, YoY/MoM as measures or dimensions — not `TO_DATE(CAST(...))` in every Genie instruction.
3. **Bridge tables** — marketing flight → orders (or campaign id on sales). Ontology cannot correlate ROAS to revenue without this.
4. **Unity Catalog comments, tags, PK/FK, data contracts** — Genie and future Ontology consume these. Tag PII; document grain on every fact.
5. **Benchmark + evaluation** — automate the 8 PRD queries plus failure cases (ambiguous “cost”, “efficiency”, snapshot summing). Gate `prod` deploys on accuracy.
6. **Dashboards on the same metric views** — exec tiles and Genie share KPIs.
7. **Genie as code** — DAB already exists (`databricks.yml` + `geniespace.json`). Add metric-view SQL/YAML to the bundle; promote `dev` → `prod`; `run_as` a **service principal** in prod, not a personal user.
8. **Permissions** — metric views inherit UC grants. Execs `SELECT` on views, not raw facts. Genie warehouse identity must match.
9. **Alerts** — PRD wants OEE < 70%, ROAS < 1, HIGH stockout. Point Databricks alerts at **metric views**, not a second copy of the formula.
10. **Vector search / unstructured** — SOP PDFs, quality NCR text, campaign briefs as a RAG index **linked by ontology IDs** (Part, Plant). Complements the KG; does not replace Metric Views.
11. **Multi-agent** — keep Executive Analyst thin on metric views; deep-dive Supplier Analyst on supplier metric views; a supervisor agent routes. Shared ontology so “supplier” means the same node.
12. **Lineage and change management** — KPI change = metric view PR, not a silent Genie instruction edit. UC lineage shows dashboards/Genie downstream.

---

## Recommended rollout

### Phase 1 — Semantic layer

Join dims in five metric views; move ROAS/CPL/OEE/PPM/revenue measures out of Genie JSON; point the space at those views; UC comments + synonyms; materialize inventory latest-day and plant-day OEE.

### Phase 2 — Ontology lite

Glossary + domains; certified answers; 15+ benchmark questions; alerts on the same measures. Follow [`ontology-uc-glossary-domains.md`](ontology-uc-glossary-domains.md).

### Phase 3 — Knowledge graph

**Done (Delta):** `ontology.kg_nodes` / `kg_edges` from dims + fact key pairs + KPI properties; object properties in `graph.yml` → OWL TBox. Use for “how is Plant X connected?” via SQL ([`kg_queries.sql`](../src/ontology/kg_queries.sql)). Do not parse Genie SQL as the system of record. OntoBricks / Neo4j remain optional later.

### Phase 4 — Platform ontology

When Genie Ontology is available in the workspace, it should **learn from** Phases 1–2, not replace them.

---

## What not to do

- Duplicate KPI logic in Genie instructions, dashboard SQL, *and* graph properties.
- One giant metric view across all five facts.
- A full OWL graph before dims are in the semantic layer.
- Treating Genie Ontology preview as something you can install today.

---

## Current repo touchpoints

| Asset | Role today | Role after this work |
| --- | --- | --- |
| `src/executive_analyst.geniespace.json` | Full semantic + routing instructions | Thin Genie config: metric views as sources, short policy text, certified SQL |
| `resources/executive_analyst.genie_space.yml` | Deploys the space | Unchanged pattern; warehouse must reach prod metric views |
| `databricks.yml` | `dev` / `prod` targets | Prod identifiers on `gold` (or prod catalog); `run_as` service principal |
| `docs/prd.md` | Agent identity, grains, sample questions | Still source of domain truth; this doc is the semantics/KG plan |

---

*Companion to `docs/prd.md`. Implement against `gold_dev` first, then promote metric views and the Genie space to prod.*
