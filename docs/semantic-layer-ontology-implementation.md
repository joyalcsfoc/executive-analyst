# Executive Analyst — Semantic Layer, Ontology & Knowledge Graph

**Client briefing.** What was built, what it prevents, and what remains open.

Supporting detail: [`prd.md`](prd.md) (domains, grains, sample questions) ·
[`ontology-uc-glossary-domains.md`](ontology-uc-glossary-domains.md) (Phase 2 runbook) ·
[`benchmark_questions.md`](../src/ontology/benchmark_questions.md) (45-question eval suite).

---

## 1. The problem this solves

- An LLM pointed at a warehouse will answer **confidently and wrongly**, because it does not know what your terms mean.
- It will average a ratio, sum a snapshot, treat bookings as revenue, and invent a join between tables that share no key.
- None of those failures produce an error. They produce a number, and the number goes into a board pack.
- **The fix is not a better prompt.** It is governed definitions the agent cannot route around.

## 2. What was built — four layers

| # | Layer | Governs | Implemented as |
| --- | --- | --- | --- |
| 1 | **Semantic layer** | KPI math, grain, dimension joins | 5 Unity Catalog metric views |
| 2 | **Ontology** | What terms mean; what must never be confused | `exec_analyst.ttl` (OWL, in Git) |
| 3 | **Knowledge graph** | How entities connect | `kg_nodes` / `kg_edges` + 2 traversal functions |
| 4 | **Agent** | Routing and policy | Genie space, defined as code |

**The organizing principle:** one file is the source of truth, and everything ontology-shaped
downstream is generated from it.

- Nothing is maintained in two places.
- Nothing can drift out of sync.
- A definition change is a Git pull request, not a UI edit nobody can review.

**By the numbers**

| Metric views | OWL classes | Object properties | Edge types | Generated artifacts | Bound measures | Benchmark questions |
| --- | --- | --- | --- | --- | --- | --- |
| 5 | 57 | 20 | 8 | 9 | 17 | 45 |

---

## 3. Layer 1 — Semantic layer

**Five Unity Catalog metric views, one per fact table.**

| Metric view | Source fact | Grain | Representative measures |
| --- | --- | --- | --- |
| `metrics_sales_order` | `fact_sales_order` | order | `total_revenue`, `total_bookings`, `total_discount`, `discount_percent`, `delivered_order_revenue` |
| `metrics_campaign_performance` | `fact_campaign_performance` | campaign_flight | `weighted_roas`, `cost_per_lead`, `total_spend`, `total_conversions` |
| `metrics_production_execution` | `fact_production_execution` | production_row | `average_oee`, `total_downtime`, `oee_below_70` |
| `metrics_inventory_snapshot` | `fact_inventory_snapshot` | snapshot | `Avg Days of Supply`, `Avg Inventory Turnover`, `Total Stock Valuation`, `is_current_snapshot` |
| `metrics_supplier_quality` | `fact_supplier_quality` | inspection | `PPM`, `Avg Quality Score`, `Total Cost of Poor Quality` |

**Features**

- **One definition per KPI**, used by every consumer — no team maintains its own version of revenue.
- **Dimension joins enabled on all five**, so answers name *Plant Manesar*, not `PLANT_KEY=7`.
- **Every join declares `at_most_one_match: true`**, and the test suite verifies it — a violated
  assumption silently fans out the join and corrupts every KPI on the view.
- **Grain is declared, not assumed** — recorded as a Unity Catalog tag on each view.
- **Renamed from legacy `mv_executive_*`** to a predictable `metrics_<fact>` convention; legacy
  names dropped automatically.

**The KPI traps encoded in the views**

- **Revenue** is `SUM(ORDER_AMOUNT)`; **Bookings** is `SUM(BOOKING_AMOUNT)` — different stages of
  the pipeline, never substituted.
- **ROAS** and **CPL** are spend-weighted rollups — never `AVG(ROAS)` or `AVG(COST_PER_LEAD)`.
- **PPM** is `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6` — a ratio of sums, never `SUM(PPM_LEVEL)`.
- **OEE** is stored 0–100, so "below 70%" is `OEE_PCT < 70`, never `< 0.70`.
- **Inventory** is point-in-time — filter `is_current_snapshot`; on-hand and valuation are never
  summed across dates.

---

## 4. Layer 2 — Ontology

**`exec_analyst.ttl` — the source of truth for meaning.**

- The Executive Analyst slice of the enterprise automotive-manufacturing ontology, **pruned to
  what the agent is actually connected to**: 5 facts, 5 metric views, 11 dimensions.
- **Class IRIs reused verbatim** from the enterprise `mfg:` namespace, so this file stays
  compatible with `automotive_manufacturing_ontology.ttl` and does not fork the enterprise model.
- **Agent-specific concepts** — KPIs, ambiguity, bindings — live in a separate `ea:` namespace.
- **Enterprise modeling rules kept:** type attributes become class taxonomies closed with
  `owl:AllDisjointClasses`; status attributes become enumerated classes labelled with the literal
  warehouse value; foreign keys become object properties with declared inverses.
- 57 classes, 20 object properties, organized by business domain.

### 4.1 What makes this ontology executable

A generic OWL file describes a domain; it cannot produce anything. This one carries a **binding
layer the enterprise ontology does not have** — annotations that tie every concept to a real
Databricks identifier.

| Annotation | Generates |
| --- | --- |
| `ea:boundToTable` / `KeyColumn` / `NameColumn` | a `kg_nodes` producer |
| `ea:boundToView` / `Measure` / `Field` | the governed `MEASURE()` the agent must use |
| `ea:boundToColumn` | an enum bound to the column carrying its controlled vocabulary |
| `ea:edgeFrom` / `edgeSubjectKey` / `edgeObjectKey` | a row set in `kg_edges` |
| `ea:domainTag` / `ea:grainTag` | Unity Catalog tags on the bound metric view |
| `ea:notSameAs` | a "never substitute these" rule in the agent instructions |
| `ea:disambiguatesTo` | an "ask the user first" rule |
| `ea:aka` | synonyms for entity matching |

### 4.2 One file in, nine artifacts out

`python src/ontology/generate.py` — or `./deploy.sh regen-tags` — reads the TTL with rdflib and rewrites:

| Output | Role |
| --- | --- |
| `tag_metric_views.sql` | Unity Catalog tags: domain, grain, kpi, glossary terms |
| `materialize_kg.sql` | `kg_nodes` + `kg_edges` DDL |
| `kg_functions.sql` | `kg_neighbors`, `kg_find_node` |
| `grant_kg.sql` | `USAGE` / `SELECT` on the graph schema |
| `kg_queries.sql` | Worked neighborhood queries |
| `genie_context.json` | 31 synonyms, 3 vocabularies, 7 conflation pairs |
| `executive_analyst.geniespace.json` | The generated agent-grounding block |
| `assert_kg_integrity.sql` | Graph integrity assertions |
| `ontology_reference.html` | Browsable page for governance review |

- Every output carries a **"do not edit by hand"** banner.
- `generate.py --check` **exits 1 if any output is stale** — it works as a CI gate.
- The Genie file is **spliced, not overwritten**: the API permits one instruction item, so
  everything below the marker `## Ontology grounding (generated)` is regenerated and the
  hand-written policy above it is preserved.

### 4.3 Conflations the agent is blocked from making

- Bookings **≠** Revenue
- Conversion **≠** SalesOrderStatus
- Discount **≠** DiscountPercent
- InventoryTurnover **≠** OEE

### 4.4 Words the agent must ask about

| Surface term | Could mean |
| --- | --- |
| "cost" | CampaignSpend · CostPerLead · COPQ · Discount |
| "efficiency" | OEE · InventoryTurnover |

### 4.5 Controlled vocabularies shipped to the agent

Exact literal column values, so the agent filters on `'ACCEPT & SORT'` rather than guessing a
spelling: **QualityDisposition**, **RiskLevel**, **SalesOrderStatus**.

---

## 5. Layer 3 — Knowledge graph

**Why it exists:** the five metric views deliberately share no join path. That is what makes KPI
math safe — and what makes *"which suppliers feed Plant X"* unanswerable. The graph answers
structural questions; it carries **no measures**.

| Asset | Contents |
| --- | --- |
| `ontology.kg_nodes` | One row per entity instance, tagged with its ontology class — Plant, ProductionLine, VehicleModel, Dealer, Part, Warehouse, Supplier, MarketingCampaign, CampaignChannel, CustomerSegment, CalendarDate |
| `ontology.kg_edges` | Distinct key pairs from facts, typed by object property — `plantHasLine`, `plantProducesModel`, `lineProducesModel`, `dealerSellsModel`, `partStockedAt` (current snapshot only), `supplierSuppliesPart`, `campaignRunsOnChannel`, `campaignTargetsSegment` |
| `kg_find_node(name)` | Resolves a business name to its node — the agent starts from what the user said |
| `kg_neighbors(type, key, rel)` | One hop in either direction, optionally filtered to a single relation |

**Features**

- **Wired into the agent as callable tools**, under `sql_functions` — deliberately *not* as data
  sources, so the agent traverses the graph instead of trying to aggregate over it.
- **Rebuilt from the ontology on every apply** — the graph cannot drift from the model.
- **Structure only, never measures** — KPI math has exactly one home, and this is not it.

**One load-bearing detail:** every function parameter is `p_`-prefixed. A SQL UDF body resolves a
bare name to a *column* in scope before a parameter, so a parameter named `node_type` silently
rewrites `e.subject_type = node_type` into `e.subject_type = n.node_type` — the function returns
zero rows, with no error. The prefix is not style.

---

## 6. Layer 4 — Agent

**A thin Genie space over governed assets. It consumes the layers below; it is not the system of record.**

**Data sources**

- The **five metric views** — the only sanctioned path to a KPI number.
- The **five fact tables** — row-level drill only, never for aggregates.
- **Two knowledge-graph functions**, attached as tools for relationship questions.

**Hand-written policy (authored once, reviewed in Git)**

- **Route to metric views first** — facts only when the user needs individual rows.
- **Never JOIN or UNION across domains** — the grains do not reconcile.
- **"How is the business doing?"** fans out to one query per domain, never a single blended query.
- **Money in INR**, formatted ₹X.XX Cr above a crore and ₹X.XX Lakh above a lakh.
- **Percents to one decimal with a `%` suffix; ROAS to two decimals.**
- **Never stack mixed units into one value column** — one column carries one number format, so a
  percentage sharing a column with rupees renders as ₹. Return one column per metric instead.
- **Prefer name fields** — `dealer_name`, `plant_name`, `part_name`, `campaign_name`, `supplier_name`.
- **Answer shape:** headline KPI with its period or snapshot, then two to four bullets on drivers.

**Generated grounding block (regenerated from the ontology, never hand-edited)**

- **17 governed measure bindings** — the exact `MEASURE()` for each business concept.
- **Conflation pairs** — the terms the agent is forbidden to substitute.
- **Ambiguous terms** — the words it must ask about before querying.
- **Three controlled vocabularies** with exact literal column values.
- **Relationship routing** — send structural questions to `kg_find_node` / `kg_neighbors` instead
  of inventing a join, plus the list of available relations.

---

## 7. In practice — what the client sees

Seven questions from the benchmark suite. Each is a place where a plausible answer would be wrong.

| Question | Mechanism | Without the ontology |
| --- | --- | --- |
| *Is revenue the same as bookings?* | `ea:notSameAs` | The two read as synonyms and pipeline gets reported as recognized sales |
| *What was our marketing cost last month?* | `ea:disambiguatesTo` — the agent asks | It silently picks one of four cost concepts and answers a question nobody asked |
| *Top 5 campaigns by ROAS* | `MEASURE(weighted_roas)` | `AVG(ROAS)` weights a ₹2,000 campaign like a ₹2 Cr one and reorders the ranking |
| *Total inventory value across all dates* | Grain guard → `is_current_snapshot` | A confident number roughly 365× too large |
| *Which plants are inefficient this week?* | Disambiguation + 0–100 threshold | `< 0.70` on a 0–100 column returns zero rows — "no plants underperforming" |
| *Which lines does Manesar run?* | `kg_find_node` → `kg_neighbors` | An invented JOIN across tables that share no key |
| *Board risk snapshot* | Three views, three grains, no UNION | One blended table where a percentage renders as currency |

The full suite is **45 questions** — 8 PRD samples, 7 disambiguation traps, and 28 in C-suite voice
across revenue, cost, customers, strategy, execution and risk. Re-run after every deploy.

---

## 8. How correctness is proven

Five independent checks. Each catches what the others structurally cannot.

| Check | Command | Catches |
| --- | --- | --- |
| **Generator consistency** | `generate.py --check` | a generated artifact drifting from the ontology |
| **Model consistency** | `test_generate.py` | an internally incoherent ontology — dangling domain/range, missing binding |
| **Live binding check** | `verify_bindings.py` | a `MEASURE()` the ontology names that does not exist in the deployed view |
| **SQL correctness** | `./deploy.sh test-metrics` | KPI-formula, dim-uniqueness, fan-out, snapshot-grain and graph-integrity regressions |
| **Agent behavior** | `benchmark_questions.md` | wrong routing, missing clarification, trap answers |

- Only the warehouse knows whether a measure really exists — which is why the live check is separate.
- It **earned its place on the first run**, finding nine bindings pointing at identifiers that do not exist.
- The SQL suite is **independent of the agent**: it catches a regressed formula even if nobody has
  asked the matching question yet.

---

## 9. Open items

### Open hazard — metric-view naming split

- The two `supply_chain` views were rebuilt in the workspace with **Title Case** measure names
  (`Avg Days of Supply`, `Total Cost of Poor Quality`); the repo's `.sql` files still declare
  **snake_case**. The other three views agree in both places.
- Bindings currently **track deployed reality**, because that is what the agent queries.
- Running `apply-metrics` with the metric-view `CREATE` tasks re-enabled would overwrite the
  deployed views, rename every measure back, and break all nine bindings — **which is why the apply
  job no longer recreates views**.
- **Resolution needed:** pick one convention, make the `.sql` files match, re-run `verify_bindings.py`.

### Relations the gold layer cannot support yet

| Missing relation | Blocked because |
| --- | --- |
| `Campaign → SalesOrder` | no bridge table joins marketing spend to orders, so revenue attribution is out of reach |
| `Plant → Part` | no fact links a plant or line to the parts it consumes; Plant→Model and Supplier→Part exist, the middle hop does not |
| `Warehouse → Plant` | `dim_warehouse` carries no confirmed plant reference |

Each becomes an object property in the ontology the moment the backing table lands — the generator
picks it up with **no other change**.

### Deliberately not implemented

| Item | Status | Reason |
| --- | --- | --- |
| UC Domains / Glossary Pages REST upsert | Deferred | API not GA; UC tags cover it as code |
| Genie Ontology product | Prep only | grants and checklist ready; product not installed |
| OWL 2 RL reasoning / triple store | Not planned | the Delta property graph is the chosen path |
| Neo4j sync / Bloom | Not planned | Delta stays the system of record |
| Liquid Clustering on gold facts | Drafted | needs the gold-owning team's sign-off; wired into no job |
| Prod Genie identifiers | Pending | space file still points at `gold_dev.*` |

---

## 10. Operating the system

### How to change meaning safely

| To change | Edit | Then run |
| --- | --- | --- |
| KPI formula, grain, join | `metrics_*.sql` | the `CREATE OR REPLACE` on the warehouse, then `verify_bindings.py` |
| Term meaning, synonym, ambiguity, binding | `exec_analyst.ttl` | `regen-tags` → `deploy` → `apply-metrics` |
| New typed relation | `exec_analyst.ttl` — object property + `ea:edgeFrom` | `regen-tags` → `deploy` → `apply-metrics` |
| Agent policy prose | `geniespace.json`, above the generated marker | `deploy` |

- **Never hand-edit a generated file** — the next `regen-tags` overwrites it.
- **Never make a silent Genie UI edit** — it is overwritten on the next deploy and leaves no review trail.

### Deployment assets

| Asset | Role |
| --- | --- |
| `databricks.yml` | bundle targets dev/prod, warehouse, `gold_catalog`, permission group |
| `resources/metric_views_job.yml` | ordered apply: `materialize_kg` → `grant_kg` → `kg_functions` → `tag_metric_views` → `grant_metric_views` → `drop_legacy` |
| `resources/validate_metric_views_job.yml` | read-only assertion suite |
| `deploy.sh` | `validate` \| `deploy` \| `apply-metrics` \| `test-metrics` \| `regen-tags` \| `open` \| `destroy` |

Grants go to `genie_space_permission_group` (default `users`) on the five views, the tagged
dimensions, and `ontology.kg_*`.

---

*Currently running on `gold_dev`. Promote views, tags, grants, graph tables and the Genie space to
`gold` when catalog ownership and identifiers are ready.*
