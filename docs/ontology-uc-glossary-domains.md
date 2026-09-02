# Executive Analyst — Ontology as Unity Catalog Glossary + Knowledge Graph

**Phase 2/3 implementation runbook.** Ontology is the **shared meaning of entities and terms**
plus their **typed relationships**; KPI math lives in the five `metrics_*` views, not here.

**Source of truth: [`src/ontology/exec_analyst.ttl`](../src/ontology/exec_analyst.ttl).** It is a
pruned, Databricks-bound copy of the enterprise `automotive_manufacturing_ontology.ttl` (team-lead
sample), scoped to exactly the five facts / five metric views / eleven dims this Genie space is
connected to. Every class carries an `ea:boundTo*` annotation pointing at the real table, view,
measure or column it means. [`src/ontology/generate.py`](../src/ontology/generate.py) reads the
TTL and regenerates everything else — UC tags, the knowledge-graph SQL, traversal functions, and
the browsable HTML reference. **Never hand-edit a generated file; edit the TTL and re-run it.**

Companion docs: [`prd.md`](prd.md) (domains, grains, sample questions),
[`semantic-layer-ontology-implementation.md`](semantic-layer-ontology-implementation.md) (what was built).

---

## Systems of record

| Piece | System of record | Job |
| --- | --- | --- |
| **Domains (UC governance)** | *(skipped)* — use view tag `domain` instead | Revenue, Marketing, Manufacturing, Inventory, Supplier Quality |
| **Ontology (classes, KPIs, enums, ambiguity, relationships)** | [`src/ontology/exec_analyst.ttl`](../src/ontology/exec_analyst.ttl) | What "Revenue", "OEE", "ROAS", "Plant" mean, how they differ, and how entities connect |
| **UC tags** | Generated from the TTL by `generate.py` → `tag_metric_views.sql` | Stops Genie treating `CONVERSIONS` as `DELIVERED` |
| **Knowledge graph (ABox)** | Generated from the TTL → `materialize_kg.sql` → `{catalog}.ontology.kg_nodes` / `kg_edges` | "Which suppliers feed the parts used on Plant X" |
| **KPI math** | Five `metrics_*` metric views | Aggregation, grain, filters |

Genie should **consume** this. Do not encode meaning only in `src/executive_analyst.geniespace.json`.

**Prerequisite:** Phase 1 (metric views + dim joins) is already in the repo — every entity in the
TTL binds to a name column that already exists.

---

## Step 0 — Entity substrate (dims) — done

Ontology without names is just keys. Confirmed in [`column_map.md`](../src/metric_views/column_map.md);
all eleven dims are joined in the five `metrics_*` views and bound to a class in the TTL.

---

## Step 1 — Unity Catalog Domains — skipped

UC Domains are optional governance labels, not required for Genie accuracy. Domain meaning is
carried instead as the `domain` tag on each metric view, generated from `ea:domainTag` in the TTL.

---

## Step 2 — Author the ontology (this is the real work)

Edit [`exec_analyst.ttl`](../src/ontology/exec_analyst.ttl) directly. Three modeling rules, carried
over from the enterprise ontology so this file stays compatible with it:

1. A **type/category** column becomes a subclass taxonomy closed with `owl:AllDisjointClasses`.
2. A **status** column becomes an `owl:oneOf` enumeration whose named individuals' `rdfs:label` is
   the literal warehouse value.
3. A **foreign key** becomes an `owl:ObjectProperty` pair with a declared `owl:inverseOf`.

Every class also carries a binding annotation (`ea:boundToTable`, `ea:boundToView`,
`ea:boundToMeasure`, `ea:boundToColumn`, …) — the thing the enterprise TTL doesn't have, and the
reason `generate.py` can produce UC tags and a knowledge graph from it. See the binding-vocabulary
section at the top of the TTL for the full annotation-property list.

### KPIs currently modeled (`ea:KPI` subclasses)

| Term | Definition | Not the same as | Bound measure |
| --- | --- | --- | --- |
| Revenue | `SUM(ORDER_AMOUNT)`, INR | Bookings | `metrics_sales_order.total_revenue` |
| Bookings | `SUM(BOOKING_AMOUNT)`, pipeline | Revenue | `total_bookings` |
| Discount | `SUM(DISCOUNT_AMOUNT)` | Discount percent | `total_discount` |
| Discount percent | `100 * discount / revenue`, unit % | Discount | `discount_percent` |
| Delivered order revenue | Revenue where `STATUS = DELIVERED` | Conversion | `delivered_order_revenue` |
| ROAS | Spend-weighted; never `AVG(ROAS)` | — | `weighted_roas` |
| Cost per lead | `SUM(spend)/SUM(leads)` | — | `cost_per_lead` |
| Conversion | Campaign `CONVERSIONS` | Delivered order | `total_conversions` |
| Campaign spend | `SUM(ACTUAL_SPEND)` | — | `total_spend` |
| OEE | Availability × performance × quality, 0–100 | Inventory turnover | `average_oee` |
| Downtime | Minutes (`DOWNTIME_MIN`) | — | `total_downtime` |
| Days of supply | Point-in-time cover | — | `average_days_of_supply` |
| Inventory turnover | Point-in-time ratio | OEE | `average_turnover` |
| Stock valuation | INR, single snapshot date | — | `total_stock_valuation` |
| PPM | `SUM(defect)/SUM(inspected)*1e6` | — | `ppm` |
| COPQ | `SUM(COST_OF_POOR_QUALITY)` | — | `copq` |
| Quality score | Average incoming score | — | `average_quality_score` |

### Ambiguous surface terms (`ea:AmbiguousTerm` subclasses)

| Term | Resolves to |
| --- | --- |
| Cost | Campaign spend, cost per lead, COPQ, or discount — ask which |
| Efficiency | OEE (production) or inventory turnover (supply chain) — ask which |

### Entities (bound to dims)

| Term | Dim / field |
| --- | --- |
| Plant, Production line | `dim_plant` / `dim_production_line` |
| Part, Warehouse | `dim_part` / `dim_warehouse` |
| Supplier | `dim_supplier` |
| Dealer, Vehicle model | `dim_dealer` / `dim_vehicle_model` |
| Campaign, Channel, Segment | `dim_campaign` / `dim_channel` / `dim_customer_segment` |
| Calendar date | `dim_date` |

### Relationships (object properties, materialized into `kg_edges`)

```text
Plant --plantHasLine--> ProductionLine --lineProducesModel--> VehicleModel
Plant --plantProducesModel--> VehicleModel        (materialized directly, single hop)
Dealer --dealerSellsModel--> VehicleModel
Part --partStockedAt--> Warehouse                 (current snapshot only)
Supplier --supplierSuppliesPart--> Part
MarketingCampaign --campaignRunsOnChannel--> CampaignChannel
MarketingCampaign --campaignTargetsSegment--> CustomerSegment
```

Every property has a declared inverse. **Known gaps** (Campaign→SalesOrder, Plant→Part,
Warehouse→Plant) are listed at the bottom of the TTL — add the object property there the moment a
backing table exists; `generate.py` picks it up with no other change. Do not invent an edge for a
join path the gold slice cannot support.

---

## Step 3 — Wire terms to assets — generated, not authored

**System of record:** UC tags on metric views and dims (`glossary_terms`, `glossary_source`),
generated from the TTL by [`generate.py`](../src/ontology/generate.py) into
[`tag_metric_views.sql`](../src/metric_views/tag_metric_views.sql). There is nothing to hand-wire —
`ea:boundToView` / `ea:boundToTable` on a class *is* the wiring.

View tags also carry `domain`, `grain`, `kpi=true` — all read from the TTL's `ea:domainTag` /
`ea:grainTag` annotations. Catalog Explorer Assign stays optional; see
[`wiring_checklist.md`](../src/ontology/wiring_checklist.md).

---

## Step 4 — Genie Knowledge Store (agent-facing ontology) — done

Meaning stays in UC metric views + generated glossary tags; Genie keeps short policy plus
certified `sql_snippets`.

| Piece | Location |
| --- | --- |
| Thin policy instructions | [`src/executive_analyst.geniespace.json`](../src/executive_analyst.geniespace.json) `text_instructions` |
| Certified measures / filters | same file → `sql_snippets.measures` / `filters` |
| Benchmark suite | [`src/ontology/benchmark_questions.md`](../src/ontology/benchmark_questions.md) |

Policy text only: INR / Cr/Lakh, ask when **cost** or **efficiency** is ambiguous (both are now
`ea:AmbiguousTerm` classes in the TTL with `ea:disambiguatesTo`), metric views first.

---

## Step 5 — Knowledge graph (ABox) + traversal tools — done

`generate.py` also produces:

| Asset | Role |
| --- | --- |
| [`materialize_kg.sql`](../src/ontology/materialize_kg.sql) | `{catalog}.ontology.kg_nodes` / `kg_edges` from bound classes + object properties |
| [`grant_kg.sql`](../src/ontology/grant_kg.sql) | `GRANT USAGE`/`SELECT` on the tables and `EXECUTE` on the two functions, to the Genie reader group |
| [`kg_functions.sql`](../src/ontology/kg_functions.sql) | `kg_neighbors` / `kg_find_node` UC functions — attached to the Genie space (or a Multi-Agent Supervisor tool) so the agent can answer relationship questions |
| [`kg_queries.sql`](../src/ontology/kg_queries.sql) | Worked neighborhood queries for the SQL editor |

Run order (already wired into `apply_metric_views`): `materialize_kg` → `grant_kg` →
`kg_functions` → `tag_metric_views` → `grant_metric_views` → `drop_legacy_mv_executive`.

`kg_neighbors` / `kg_find_node` are attached in `executive_analyst.geniespace.json` under
`instructions.sql_functions` — `[{ "id": <32-hex>, "identifier": "<catalog>.ontology.<fn>" }]`.
There is **no** `functions` key under `data_sources`; function attachment is an instruction, not a
data source. Two further API constraints the space file has to respect:

- `instructions.text_instructions` accepts **at most one item**. `generate.py` therefore appends the
  ontology block to the single hand-written instruction, splitting on `## Ontology grounding
  (generated)` — never add a second entry, the deploy fails with `Invalid export proto`.
- On read-back the API normalizes `data_sources.metric_views` into `tables` and splits
  `content` into one item per line, so a `bundle generate genie-space` round-trip reshapes the
  file without changing its meaning. Prefer hand-editing to `--force` regeneration.

---

## Step 6 — Genie Ontology product — prep only, not installed

Genie Ontology (the learned graph product) is not implemented here — Steps 0–5 are what make its
eventual preview effective when enabled. Checklist:
[`genie_ontology_prep.md`](../src/ontology/genie_ontology_prep.md).

---

## What not to do

- Duplicate definitions in Genie JSON vs the TTL vs dashboards.
- Merge five facts into one ontology view.
- Hand-edit any generated file (`tag_metric_views.sql`, `materialize_kg.sql`, `grant_kg.sql`,
  `kg_functions.sql`, `kg_queries.sql`, `ontology_reference.html`) — edit `exec_analyst.ttl` and
  run `./deploy.sh regen-tags`.
- Encode ontology only in `src/executive_analyst.geniespace.json`.
- Invent a Campaign→Order, Plant→Part, or Warehouse→Plant edge without a backing table.

---

## Repo touchpoints

| Asset | Role |
| --- | --- |
| `src/ontology/exec_analyst.ttl` | **Ontology source of truth** — classes, KPIs, enums, ambiguous terms, object properties + bindings |
| `src/ontology/generate.py` | TTL → tags SQL, KG SQL, KG functions, HTML reference |
| `src/metric_views/tag_metric_views.sql` | GENERATED UC tags |
| `src/metric_views/grant_metric_views.sql` | `GRANT SELECT` on `metrics_*` + tagged dims |
| `src/ontology/materialize_kg.sql` / `grant_kg.sql` / `kg_functions.sql` / `kg_queries.sql` | GENERATED knowledge graph + traversal tools |
| `ontology_reference.html` (repo root) | GENERATED browsable reference for team review |
| `src/executive_analyst.geniespace.json` | Thin policy + certified `sql_snippets` (Step 4) |
| `src/ontology/wiring_checklist.md` | Optional Catalog Explorer Assign checklist |
| `src/ontology/benchmark_questions.md` | Genie eval questions |
| `src/ontology/genie_ontology_prep.md` | Step 6 readiness checklist |

---

*Implement against `gold_dev` first, then promote the TTL bindings, tags, KG, and metric views to prod.*
