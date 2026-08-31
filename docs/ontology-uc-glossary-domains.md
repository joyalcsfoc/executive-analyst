# Executive Analyst — Ontology as Unity Catalog Glossary + Domains

**Phase 2 implementation runbook.** Ontology is the **shared meaning of entities and terms**, not KPI math. KPI math already lives in the five `metrics_*` views.

Implement ontology as **Unity Catalog Glossary + Domains first**, then Genie certified answers. Do **not** start with OWL. Do **not** wait for Genie Ontology preview.

Companion docs: [`prd.md`](prd.md) (domains, grains, sample questions), [`semantic-layer-ontology-knowledge-graph.md`](semantic-layer-ontology-knowledge-graph.md) (layers, phases, what not to do), and [`semantic-layer-ontology-implementation.md`](semantic-layer-ontology-implementation.md) (**what was built** in this repo).

---

## Systems of record

| Piece | System of record | Job |
| --- | --- | --- |
| **Domains** | *(skipped)* — use view tag `domain` instead | Revenue, Marketing, Manufacturing, Inventory, Supplier Quality |
| **Glossary terms** | Unity Catalog + [`src/ontology/glossary.yml`](../src/ontology/glossary.yml) | What “Revenue”, “OEE”, “ROAS”, “Plant” mean, and how they differ |
| **Links** | Term → metric view / column | Stops Genie treating `CONVERSIONS` as `DELIVERED` |
| **Entities** | Dims + later graph | Plant, Part, Dealer, Campaign, etc. |
| **KPI math** | Five `metrics_*` metric views | Aggregation, grain, filters |

Genie should **consume** this. Do not encode meaning only in `src/executive_analyst.geniespace.json`.

**Prerequisite:** Phase 1 (metric views) is already in the repo. Finish **dimension joins** before a formal entity graph — otherwise “Plant” is still `PLANT_KEY`, not a named entity.

---

## Step 0 — Finish the entity substrate (dims)

Ontology without names is just keys.

1. `DESCRIBE TABLE` facts and `gold_dev.dim.*`.
2. Fill [`src/metric_views/column_map.md`](../src/metric_views/column_map.md).
3. Uncomment `TODO: dim join` in each `metrics_*.sql` (or keep joins enabled if already confirmed).
4. Re-run `./deploy.sh apply-metrics --target dev`.

Until that is done, glossary terms still attach to measures; they cannot attach cleanly to **Plant / Dealer / Part** names.

---

## Step 1 — Create five Unity Catalog domains — **SKIPPED**

UC Domains are **optional governance** (ownership labels). They are **not required** for Genie accuracy or for this glossary. Skipped for now.

Domain meaning is carried instead as Unity Catalog **tags** on the five metric views (`domain=revenue|marketing|…`) via [`src/metric_views/tag_metric_views.sql`](../src/metric_views/tag_metric_views.sql) (runs as the last task of `apply_metric_views`).

You can create formal UC Domains later without changing glossary YAML.

---

## Step 2 — Author the glossary (this is the real ontology)

**Git source of truth:** [`src/ontology/glossary.yml`](../src/ontology/glossary.yml) — definitions, owners, related terms, and `links_to` view/measure/field/table paths.

**Do not invent definitions only in the UI.** Create or update Catalog Explorer glossary terms from that file.

### Catalog Explorer checklist (manual)

1. Open **Catalog Explorer → Glossary** (or Governance → Glossary, depending on workspace UI).
2. For each entry in `glossary.yml`:
   - Create term with `name` and `definition`.
   - Set owner from `owner` (finance, marketing, manufacturing, supply_chain, quality, executive_analyst).
   - Add **related** / **not the same as** links using `related` / `not_same_as` ids.
   - **Assign** the term to each asset in `links_to` (metric view + measure or field; dim table where listed).
3. Start with high-value disambiguation terms: **Revenue**, **OEE**, **Conversion (marketing)** (vs Delivered order), then finish the rest from the file.
4. After schema/KPI changes: edit `glossary.yml` in Git first, then update the UI term to match.

Prod: same term names; `links_to` paths use catalog `gold` instead of `gold_dev`.

### Measures (link to metric views)

| Term | Definition | Related / not the same as | Link to |
| --- | --- | --- | --- |
| **Revenue** | Sum of `ORDER_AMOUNT`. Default sales KPI. INR. | Not Bookings | `metrics_sales_order.total_revenue` |
| **Bookings** | Sum of `BOOKING_AMOUNT`. Pipeline, not recognized revenue. | Not Revenue | `total_bookings` |
| **Discount** | Sum of `DISCOUNT_AMOUNT`. | One sense of “cost” | `total_discount` |
| **Delivered order** | `STATUS = 'DELIVERED'`. Pipeline: PROCESSING → CONFIRMED → DELIVERED. | Not marketing Conversion | `delivered_order_revenue` |
| **ROAS** | Spend-weighted return on ad spend. Never `AVG(ROAS)`. > 1.0 = positive. | | `weighted_roas` |
| **CPL** | Spend / leads. Never `AVG(COST_PER_LEAD)`. | Ambiguous “cost” | `cost_per_lead` |
| **Conversion (marketing)** | Campaign `CONVERSIONS`. | Not Delivered order | marketing measure |
| **OEE** | Availability × Performance × Quality, stored **0–100** percent on gold_dev. “Below 70%” = `< 70`. | One sense of “efficiency” | `average_oee`, `oee_below_70` |
| **Downtime** | Minutes (`DOWNTIME_MIN`). | | `total_downtime` |
| **Stockout risk** | LOW / MEDIUM / HIGH. HIGH = on-hand below safety stock. Point-in-time. | | `stockout_risk`, `high_stockout` |
| **Days of supply** | Point-in-time cover. Do not sum across dates. | | `avg_days_of_supply` |
| **Inventory turnover** | Other sense of “efficiency”. | Not OEE | inventory turnover measure |
| **PPM** | `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6`. Never `SUM(PPM_LEVEL)`. | | `ppm` |
| **COPQ** | Cost of poor quality, INR. Another sense of “cost”. | | `copq` |

Those distinctions already exist as comments/synonyms in the SQL views (for example revenue vs bookings in `metrics_sales_order.sql`). The glossary **promotes** them to a shared, owned definition.

### Entities (link after dim joins)

| Term | Meaning | Dim / field |
| --- | --- | --- |
| Plant | Manufacturing site | `dim_plant` → `plant_name` |
| Production line | Line inside a plant | `dim_production_line` → `line_name` |
| Part | SKU / component | `dim_part` → `part_name` |
| Warehouse | Stock location | `dim_warehouse` → `warehouse_name` |
| Supplier | Incoming-quality vendor | `dim_supplier` → `supplier_name` |
| Dealer | Sales channel partner | `dim_dealer` → `dealer_name` |
| Model | Vehicle / product model | `dim_vehicle_model` → `model_name` |
| Campaign / Channel / Segment | Marketing flight dimensions | `dim_campaign` / `dim_channel` / `dim_customer_segment` |

Entity relationships stay **conceptual** until the knowledge-graph phase:

```text
Plant --hasLine--> ProductionLine --runs--> ProductionOrder
Part --stockedAt--> Warehouse
Supplier --supplies--> Part --inspectedIn--> QualityInspection
Dealer --places--> SalesOrder --for--> Model
Campaign --generates--> Lead   -- (needs gold bridge) --> SalesOrder
```

Do **not** invent Campaign → Order edges until gold has a bridge table (PRD §8.2).

---

## Step 3 — Wire terms to assets (so Genie can use them) — **done as code**

**System of record:** UC tags on metric views and dims (`glossary_terms`, `glossary_source`), applied by [`src/metric_views/tag_metric_views.sql`](../src/metric_views/tag_metric_views.sql). Definitions remain in [`src/ontology/glossary.yml`](../src/ontology/glossary.yml).

| Wire | How |
| --- | --- |
| Term → view | Tag `glossary_terms` = comma-separated term ids on each `metrics_*` |
| Term → dim | Same tags on `dim.dim_*` tables listed in `links_to` |
| Comments | Already in metric-view YAML `comment:` / measure comments |
| Related terms | In `glossary.yml` (`related` / `not_same_as`) |
| Catalog Explorer Assign | **Optional** UI mirror — track in [`src/ontology/wiring_checklist.md`](../src/ontology/wiring_checklist.md) |

View tags also keep:

- `domain` = `revenue` | `marketing` | `manufacturing` | `inventory` | `supplier_quality`
- `grain` = `order` | `campaign_flight` | `production_row` | `snapshot` | `inspection`
- `kpi` = `true`

Ambiguous terms `cost` / `efficiency` have no asset links (empty `links_to`); Genie clarification stays until Step 4.

**Not in this step:** Genie instruction thinning / certified SQL (Step 4).

---

## Step 4 — Genie Knowledge Store (agent-facing ontology) — **done**

Meaning stays in UC metric views + glossary tags; Genie keeps **short policy** plus **certified `sql_snippets`**.

| Piece | Location |
| --- | --- |
| Thin policy instructions | [`src/executive_analyst.geniespace.json`](../src/executive_analyst.geniespace.json) `text_instructions` |
| Certified measures / filters | same file → `sql_snippets.measures` / `filters` |
| Benchmark suite (15+) | [`src/ontology/benchmark_questions.md`](../src/ontology/benchmark_questions.md) |
| Sample question chips (15) | Genie JSON `config.sample_questions` |

### Certified bindings (must not drift)

| Intent | Binding |
| --- | --- |
| OEE below 70% | `oee_below_70` / `OEE_PCT < 70` (**0–100** scale on gold_dev) |
| High stockout | `high_stockout` + `is_current_snapshot` |
| Revenue | `MEASURE(total_revenue)` on `metrics_sales_order` |
| ROAS | `MEASURE(weighted_roas)` — never `AVG(ROAS)` |
| Conversions | marketing `MEASURE(total_conversions)` — not DELIVERED orders |

Policy text only: INR / Cr/Lakh, ask when **cost** or **efficiency** is ambiguous, metric views first. Do not re-encode KPI math in long Genie prompts.

Redeploy Genie after JSON edits: `./deploy.sh deploy --target dev` (and `apply-metrics` if manufacturing OEE threshold changed).

---

## Step 5 — As-code in this repo — **done**

1. **Done:** [`src/ontology/glossary.yml`](../src/ontology/glossary.yml) — terms, owners, related terms, `links_to`.
2. **Done:** tags via [`src/metric_views/tag_metric_views.sql`](../src/metric_views/tag_metric_views.sql) on `apply_metric_views` (`domain` / `grain` / `kpi` / `glossary_terms` / `glossary_source` on views + dims). Regenerate from YAML with [`src/ontology/generate_tag_sql.py`](../src/ontology/generate_tag_sql.py) so `glossary_terms` cannot drift from `links_to`.
3. **Done:** optional UI checklist [`src/ontology/wiring_checklist.md`](../src/ontology/wiring_checklist.md).
4. **Deferred:** glossary REST/SDK upsert job — Databricks Catalog Explorer Glossary API is not GA. Do **not** invent a custom glossary table/App; tags + YAML are the system of record until a public API exists. Formal Glossary/Pages Assign stays optional (see checklist).

Owners review PRs the same way as metric-view changes. KPI or term change = Git PR, not a silent Genie edit.

---

## Step 6 — Prepare for Genie Ontology (do not “install” it) — **done as prep**

Genie Ontology (announced mid-2026) is a **learned** graph: tables, queries, dashboards, popularity, glossary, metric views, ACLs. You cannot usefully implement it as a project artifact.

Prep in this repo:

1. **Done (Steps 0–5):** real semantics in metric views + glossary + UC tags + certified Genie SQL (not Genie text alone).
2. **Done:** `GRANT SELECT` on five `metrics_*` + tagged dims via [`src/metric_views/grant_metric_views.sql`](../src/metric_views/grant_metric_views.sql) (`grant_metric_views` task; principal = `genie_space_permission_group`).
3. **Operational:** Table Insights / column popularity from real Genie usage — run [`benchmark_questions.md`](../src/ontology/benchmark_questions.md) after deploy (see checklist).
4. **Hygiene:** Genie sources prefer `metrics_inventory_snapshot` only (legacy `fact_inventory_snapshot_metric_view` removed from the space JSON).

Checklist: [`src/ontology/genie_ontology_prep.md`](../src/ontology/genie_ontology_prep.md).

When the preview is on in the workspace, it should **learn from** steps 1–5 + grants/usage — not replace them. No OWL or Ontology install in this step.

---

## Step 7 — Formal OWL (TBox generated; inference later)

**Done (seed):** [`src/ontology/generate_owl.py`](../src/ontology/generate_owl.py) compiles [`glossary.yml`](../src/ontology/glossary.yml) → [`exec_analyst.ttl`](../src/ontology/exec_analyst.ttl).

| Decision | Value |
| --- | --- |
| Base IRI | `https://focaloid.com/ontology/executive-analyst#` |
| Prefix | `ea:` |
| Format | Turtle (generated, committed) |
| SoR | Still `glossary.yml` — never hand-edit the `.ttl` |

Mapping: terms → `owl:Class` under `ea:Entity` / `ea:Measure` / `ea:AmbiguousTerm`; `related` → `skos:related`; `not_same_as` → `owl:disjointWith`; `links_to` → `ea:realizedBy*` annotations (catalog-relative; no `gold_dev` in IRIs).

```bash
pip install -r src/ontology/requirements.txt
./deploy.sh regen-tags                    # also refreshes tag SQL
python src/ontology/generate_owl.py --check
```

Open `exec_analyst.ttl` in **Protégé to review only** — do not save over the generated file. KPI math stays in metric views; Genie does not load this Turtle.

**Still later:** Databricks Labs [OntoBricks](https://github.com/databrickslabs/ontobricks/), OWL 2 RL / SHACL, RDF triples. **Phase 3 Delta property graph is implemented:** [`materialize_kg.sql`](../src/ontology/materialize_kg.sql) builds `ontology.kg_nodes` / `kg_edges`; object properties live in [`graph.yml`](../src/ontology/graph.yml).

Skip inventing Campaign → Order edges until gold has a bridge table (PRD §8.2).

---

## Phase 3 — Delta knowledge graph (implemented)

| Asset | Role |
| --- | --- |
| [`graph.yml`](../src/ontology/graph.yml) | Typed edges (`hasLine`, `stockedAt`, …) |
| [`materialize_kg.sql`](../src/ontology/materialize_kg.sql) | Materialize nodes/edges on `apply-metrics` |
| [`kg_queries.sql`](../src/ontology/kg_queries.sql) | SQL neighborhood examples |

Protégé + TTL = meaning (TBox). `kg_*` tables = instances (ABox). Not a Genie source.

---

## Suggested order of work

1. Confirm dim names and enable joins (entity names) — **done** (Step 0).
2. ~~Create 5 UC domains~~ — **skipped**; use view tags instead.
3. Glossary terms in Git (`glossary.yml`) + Catalog Explorer create/link — **Step 2**.
4. Wire terms to assets via UC tags (`glossary_terms`) + checklist — **Step 3 done**.
5. Certified SQL + 15 benchmark questions; shrink Genie instructions — **Step 4 done**.
6. As-code packaging — **Step 5 done** (YAML + tags + generator; REST upsert deferred until Glossary API).
7. Genie Ontology prep — **Step 6 done as prep** (grants as code, hygiene, checklist; enable Ontology only when workspace has preview).
8. Optional later: glossary API apply job when GA; formal UC Domains / Pages if workspace has them.
9. **Done (Phase 3):** Delta entity graph [`materialize_kg.sql`](../src/ontology/materialize_kg.sql); OWL object properties from [`graph.yml`](../src/ontology/graph.yml). OntoBricks / Neo4j optional later.

---

## What not to do

- Duplicate definitions in Genie JSON vs glossary vs dashboards.
- Merge five facts into one ontology view.
- Build OWL object properties / OntoBricks before dims.
- Hand-edit `exec_analyst.ttl` or save over it from Protégé (edit `glossary.yml`, then `./deploy.sh regen-tags`).
- Encode ontology only in `src/executive_analyst.geniespace.json`.
- Invent Campaign → Order edges without a gold bridge table.

---

## Repo touchpoints

| Asset | Role for ontology |
| --- | --- |
| `src/metric_views/metrics_*.sql` | KPI math + comments/synonyms; join dims so entity terms have names |
| `src/metric_views/column_map.md` | Confirmed dim keys and name columns |
| `src/metric_views/tag_metric_views.sql` | UC tags `domain` / `grain` / `kpi` / `glossary_terms` / `glossary_source` on views + dims (generated) |
| `src/metric_views/grant_metric_views.sql` | `GRANT SELECT` on five `metrics_*` + tagged dims (Step 6 ACL prep) |
| `src/ontology/generate_tag_sql.py` | Regenerates `tag_metric_views.sql` from `glossary.yml` `links_to` |
| `src/ontology/generate_owl.py` | Regenerates `exec_analyst.ttl` (OWL TBox) from glossary |
| `src/ontology/exec_analyst.ttl` | GENERATED Turtle — Protégé review only; not Genie runtime |
| `src/executive_analyst.geniespace.json` | Thin policy + certified `sql_snippets` (Step 4 Knowledge Store) |
| `src/ontology/glossary.yml` | **Git source of truth** for glossary terms |
| `src/ontology/wiring_checklist.md` | Optional Catalog Explorer Assign checklist (deferred until Glossary Pages) |
| `src/ontology/benchmark_questions.md` | 15+ Genie eval questions + certified smoke list |
| `src/ontology/genie_ontology_prep.md` | Step 6 readiness checklist (grants, popularity, preview) |
| This doc | Runbook; Steps 1 skipped; 2–6 done as prep; Step 7 TBox generated (OntoBricks/inference later) |
| `docs/semantic-layer-ontology-knowledge-graph.md` | Layer design and Phases 1–4 |

---

*Implement against `gold_dev` first, then promote glossary links, tags, and metric views to prod.*
