# Executive Analyst — four-scenario demo script

One question, asked four ways. Every question below is engineered so the answer
**flips at exactly one boundary** — that boundary is the thing being sold.

## The four scenarios

| # | Scenario | What it actually is in this repo | Where the meaning lives |
| - | -------- | -------------------------------- | ----------------------- |
| **S1** | **Genie, no context** | A Genie space pointed at the five raw `*_analytics` fact tables + `dim.*`. No descriptions, no synonyms, no instructions, no sample questions. Pure text-to-SQL over column names. | Nowhere. Inferred from identifiers. |
| **S2** | **Genie + context** | Same raw tables, plus what you can hand-curate in the space: table/column descriptions, synonyms, and the `instructions.text_instructions` prose — the `data_sources.tables[].column_configs` half of [`executive_analyst.geniespace.json`](../executive_analyst.geniespace.json). | Prose in the prompt. Advisory. |
| **S3** | **Genie agent + semantic layer** | The five UC metric views ([`src/metric_views/`](../metric_views/)) as data sources, `MEASURE(...)` measures, certified `sql_snippets` (filters + measures), dim joins declared with `rely: at_most_one_match`, and the [`src/tests/`](../tests/) assertion job in CI. | In Unity Catalog. Enforced, versioned, testable. |
| **S4** | **+ ontology & knowledge graph** | [`exec_analyst.ttl`](exec_analyst.ttl) as single source of truth → generated UC tags/comments, [`genie_context.json`](genie_context.json) (`aka`, `notSameAs`, `disambiguatesTo`, enum closures), `ontology.kg_nodes`/`kg_edges` + `kg_find_node`/`kg_neighbors` attached as agent tools, `assert_kg_integrity` in CI. | In the ontology. One edit regenerates every artifact. |

S1→S2 is *context*. S2→S3 is *governance* (the definition stops being prose).
S3→S4 is *meaning* (what a word denotes, and how entities connect).

> ### ⚠️ Stage safety — read before you demo live
> Per [`exec_analyst.ttl`](exec_analyst.ttl) §8, `gold_dev_analytics` has a
> silver→gold load defect: `fact_sales_order.MODEL_KEY` is `-1` on all rows, and
> `ORDER_AMOUNT`, `DISCOUNT_AMOUNT`, `QUANTITY`, `STATUS` are null — so
> `total_revenue`, `discount_percent`, `total_quantity`, `delivered_order_revenue`
> return **NULL**. Marketing has the same defect in `ROAS` and `LEADS`, breaking
> `weighted_roas` and `cost_per_lead`.
>
> **Demo-safe on numbers:** manufacturing, inventory, supplier quality, and every
> KG question. **Revenue/marketing questions (B1, B2, B3, A-none):** demo them on
> the **generated SQL side by side**, not the number. Say so out loud — it lands
> better than a NULL nobody explains.

---

# THE ONE QUESTION

If you get one slide and one question, ask this — four clauses, one per layer,
all four scenarios answer it differently, and every domain it touches has real
data:

> ### "How much stock is sitting in the Pune depot right now, which SKUs there are at risk of running out, who supplies them, and what is it costing us?"

Four clauses, four boundaries:

| Clause | Layer it tests | The trap |
| ------ | -------------- | -------- |
| "how much stock … **right now**" | S1→S2 (grain) | Snapshot fact. Summing across dates inflates by the retention window. |
| "**depot**" / "**SKUs**" / "**who supplies**" | S3→S4 (`ea:aka`) | None of those three words appears anywhere in the schema. |
| "**at risk of running out**" | S3→S4 (closed enum) | `STOCKOUT_RISK` has four bands. `'HIGH'` alone drops every `CRITICAL` part. |
| "**who supplies them**" | S4 only (KG) | No join path at fact grain between inventory and supplier quality. |
| "what is it **costing** us" | S3→S4 (`ea:Cost`) | Four valid senses. The right move is to ask, not to answer. |

## What each scenario does with it

**S1 — Genie, no context.** Answers all of it, confidently, and every part is wrong.

```sql
SELECT SUM(STOCK_VALUATION) AS stock_value, COUNT(*) AS parts_at_risk
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot
WHERE  STOCKOUT_RISK = 'HIGH'            -- drops CRITICAL
-- no snapshot-date filter               -- summed over every day retained
-- "depot"/"SKU"/"vendor" matched nothing; WAREHOUSE_KEY never resolved to Pune
-- "who supplies them" silently dropped from the answer
-- "costing us" answered as STOCK_VALUATION — a fifth sense of cost it invented
```

Result: **one inflated number**, scoped to the wrong risk band, for the wrong
warehouse (or all of them), with two of the four clauses quietly ignored.

**S2 — Genie + context.** Grain and units come right. Vocabulary and structure don't.

```sql
SELECT SUM(STOCK_VALUATION) AS stock_value
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot
WHERE  SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM …)   -- ✅ prose worked
  AND  STOCKOUT_RISK = 'HIGH'                                       -- ❌ still drops CRITICAL
```

Fixed: the date filter, because a table description told it to. Still broken:
"depot" and "SKU" match nothing, `WAREHOUSE_KEY` returns as a surrogate integer,
the supplier clause is unanswerable, and "costing us" gets a guess. And it is
**re-derived per phrasing** — ask "value of stock at the Pune depot" tomorrow and
the date filter may not come back.

**S3 — + semantic layer.** Governed, repeatable, and still answering the wrong question.

```sql
SELECT `Warehouse Name`,
       MEASURE(`Total Stock Valuation`) AS stock_value
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  is_current_snapshot = true        -- ✅ structural, not prose
  AND  high_stockout = true              -- ❌ certified field = 'HIGH' only
  AND  `Warehouse Name` ILIKE '%Pune%'   -- ✅ name, not surrogate key
GROUP BY 1
```

Fixed: grain is a field not a filter it has to remember, valuation is a certified
measure, the dim join is asserted non-fanning, and the same SQL comes back for
every paraphrase. Still broken: **`high_stockout` is `HIGH` only** — the
certified field is confidently, reproducibly incomplete. "who supplies them" has
no join path. "costing us" is answered with `Total Cost of Poor Quality` or
`Total Stock Valuation` — never asked about.

**S4 — + ontology & KG.** Three governed queries and one clarifying question.

```sql
-- 1. stock + at-risk parts: enum from the ontology, not the certified boolean
SELECT `Part Name`, `Stockout Risk`,
       MEASURE(`Total Stock Valuation`) AS stock_value
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  is_current_snapshot = true
  AND  `Stockout Risk` IN ('CRITICAL','HIGH')     -- ✅ full risk band
  AND  `Warehouse Name` ILIKE '%Pune%'            -- ✅ "depot" → Warehouse (ea:aka)
GROUP BY 1, 2 ORDER BY 2, 3 DESC

-- 2. who supplies them: graph, because no fact joins these two domains
SELECT w.node_name AS warehouse, p.node_name AS part, s.node_name AS supplier
FROM       gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL  gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL  gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s

-- 3. then, and only then, the KPI on those suppliers
SELECT `Supplier Name`, MEASURE(PPM), MEASURE(`Total Cost of Poor Quality`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_supplier_quality
WHERE  `Supplier Name` IN (…from step 2…)
GROUP BY 1
```

…and on the last clause it **stops and asks**: *"'costing us' could mean cost of
poor quality on those suppliers, the value of the stock itself, or campaign
spend — which did you mean?"* (`ea:Cost disambiguatesTo` — four senses.)

## The one-line summary for the slide

| | Stock value | At-risk parts | Who supplies them | "Costing us" |
| - | - | - | - | - |
| **S1** no context | inflated ×N days | HIGH only | ignored | guessed |
| **S2** + context | ✅ (if it obeys the prose) | HIGH only | ignored | guessed |
| **S3** + semantic layer | ✅ certified, repeatable | HIGH only | no path | guessed |
| **S4** + ontology & KG | ✅ certified | **CRITICAL + HIGH** | **2-hop traversal** | **asks** |

S1 and S2 both hand you a number. S3 hands you a number you can trust to be
computed the same way tomorrow. **S4 is the first one that answers the question
that was actually asked** — and the first one that admits when it can't.

### Three things to verify before you run this live

1. **A warehouse whose name contains "Pune" must exist.** Check:
   `SELECT node_name FROM gold_dev_analytics.ontology.kg_nodes WHERE node_type = 'Warehouse'` —
   substitute a real name into every clause if not.
2. **`is_current_snapshot` and `high_stockout` must exist in the *deployed* view.**
   Per TTL §7.1 the deployed `metrics_inventory_snapshot` uses display names
   (`Part Name`, `Stockout Risk`, `Total Stock Valuation`) that the repo `.sql`
   does not. Run `python src/ontology/verify_bindings.py` and fix the S3/S4 SQL
   above to whatever it reports.
3. **`CRITICAL` must actually occur in the data**, or the S3-vs-S4 difference is
   real in principle but invisible on stage:
   `SELECT STOCKOUT_RISK, COUNT(*) FROM …fact_inventory_snapshot WHERE SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM …) GROUP BY 1`.
   If no `CRITICAL` rows exist, swap the enum beat for the `MEDIUM` watchlist
   (`restock_candidate`) or lead with the supplier hop instead.

---

## Act 0 — Why an agent instead of Genie-in-the-UI (30 seconds, no data)

S1 vs S2 is a question about context. "Agent vs Genie code" is a question about
**lifecycle**, and no single business question proves it. This table does:

| Ask the room | Genie space configured in the UI | This agent |
| ------------ | -------------------------------- | ---------- |
| "Who changed the revenue definition, and when?" | No answer. UI edits leave no diff. | `git log src/metric_views/metrics_sales_order.sql` |
| "Prove ROAS is still weighted after last week's edit." | Ask it and hope. | `./deploy.sh test-metrics` — `assert_kpi_formulas` fails the job. |
| "Ship the same agent to prod." | Re-type it. | `./deploy.sh deploy --target prod` |
| "One team renamed a KPI in 3 places. Did they miss one?" | Manual audit. | Edit the TTL, `regen-tags` — 6 artifacts regenerate, hand-editing is banned. |
| "Can it call a tool, not just write SELECTs?" | No. | `kg_find_node` / `kg_neighbors` attached as `sql_functions`. |
| "Is a dim join silently fanning out and inflating every KPI?" | Unknowable. | `assert_dim_uniqueness` — that's exactly what it tests. |

Then move to the data questions.

---

## Act A — S1 → S2: context stops the confident wrong answer

The failure mode is never a refusal. S1 returns **a number a CFO would read aloud**.

| # | Ask this | S1 (no context) | S2 (context) | Flips at | Safe |
| - | -------- | --------------- | ------------ | -------- | ---- |
| **A1** | "Which plants were below the 70% OEE standard last week?" | `WHERE OEE_PCT < 0.7` on a 0–100 column → **zero rows**, reported as "all plants are healthy" | Column description states 0–100, "below 70% means `OEE_PCT < 70`" → real list | S1→S2 | ✅ |
| **A2** | "What's our total inventory value right now?" | `SUM(STOCK_VALUATION)` across **every snapshot date** — the answer is inflated by the number of days retained | Table description says point-in-time, filter to latest `SNAPSHOT_DATE_KEY` | S1→S2 (S3 makes it structural: `is_current_snapshot`) | ✅ |
| **A3** | "Supplier defect rate (PPM) this quarter" | `AVG(PPM_LEVEL)` or worse `SUM(PPM_LEVEL)` — a per-row ratio averaged | Description: roll up as `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6` | S1→S2 | ✅ |
| **A4** | "Which parts are below safety stock?" | Guesses `SAFETY_STOCK` / `QTY_ON_HAND`; real columns are `SAFETY_STOCK_QTY` / `QUANTITY_ON_HAND` → error, or it silently picks a neighbouring column | Synonyms carry both spellings onto the real columns | S1→S2 | ✅ |
| **A5** | "How's our energy use per line?" | No column literally named that; `ENERGY_CONSUMPTION` (the PRD's name) doesn't exist either | Synonym list on `ENERGY_CONSUMED_KWH` includes both | S1→S2 | ✅ |

**Lead with A1.** A silently-empty result set reported as good news is the single
most expensive failure in this deck.

---

## Act B — S2 → S3: the semantic layer makes it *repeatable*, not just right

S2 already *says* "never `AVG(ROAS)`". The point of Act B is that prose is
advisory: it holds for the question you tested and drifts on the paraphrase.

| # | Ask this | S2 (prose context) | S3 (metric views) | Flips at | Safe |
| - | -------- | ------------------ | ----------------- | -------- | ---- |
| **B1** | "Average ROAS by channel last month" | Re-derives `SUM(ROAS*SPEND)/SUM(SPEND)` from the instruction — correct **when it follows it** | `MEASURE(weighted_roas)`. One definition, in UC, asserted in CI | S2→S3 | SQL only |
| **B2** | "Show discount as a share of revenue this month" | May average per-order ratios, or render a percent with a ₹ prefix | `MEASURE(discount_percent)` — `100*SUM(disc)/SUM(rev)`, unit declared 0–100 in the view | S2→S3 | SQL only |
| **B3** | "Revenue by dealer" | Fact carries `DEALER_KEY` only → surrogate keys, or it invents the `dim_dealer` join with no uniqueness guarantee (a dup dim row fans out and inflates every measure) | `dealer_name` field, join declared `rely: at_most_one_match`, and `assert_dim_uniqueness` proves the assumption holds | S2→S3 | SQL only |
| **B4** | **The determinism test.** Ask the *same* thing three ways in three fresh sessions: "ROAS by channel" / "ad return per channel" / "which channel gives the best return on spend?" | 2–3 different SQL shapes, 2–3 different numbers | The same `MEASURE(weighted_roas)` every time | S2→S3 | SQL only |
| **B5** | "Which lines are running under the OEE standard?" | Re-derives the threshold; `< 70` vs `< 0.7` vs `< 70%` is a coin flip per phrasing | `oee_below_70` — the threshold is a governed field, not a literal in generated SQL | S2→S3 | ✅ |

**B4 is the semantic-layer slide.** Nobody argues with "same question, same
number, every time." Screenshot the three S2 answers next to the one S3 answer.

---

## Act C — S3 → S4: the ontology decides what the *word* means

A metric view governs how a KPI is computed. It cannot tell you which KPI the
user meant. That is the ontology's job (`ea:aka`, `ea:notSameAs`,
`ea:disambiguatesTo`, and enums closed with `owl:oneOf`).

| # | Ask this | S3 (semantic layer) | S4 (+ ontology) | Backing | Safe |
| - | -------- | ------------------- | --------------- | ------- | ---- |
| **C1** | "What did we spend last month?" | Picks one governed measure — probably `total_spend` — and answers with total confidence. Correctly computed, **wrong question answered**. | Asks which: campaign spend, cost per lead, cost of poor quality, or order discount | `ea:Cost disambiguatesTo` (4 senses) | ✅ |
| **C2** | "Which plants are most efficient?" | Defaults to OEE, silently | Asks: production OEE, or inventory turnover? | `ea:Efficiency`, `OEE notSameAs InventoryTurnover` | ✅ |
| **C3** | "How many conversions did we get last month?" | Reasonable chance it counts orders at `STATUS='DELIVERED'` | `MEASURE(total_conversions)` on marketing only, and states *why* DELIVERED is not a conversion | `ea:Conversion notSameAs mfg:SalesOrderStatus` | ✅ |
| **C4** | **"How's our turnover?"** | Picks whichever it saw first | Surfaces the collision: "turnover" is an `aka` for **both** `Revenue` (topline) and `InventoryTurnover` (stock turns) → asks | `ea:aka` collision across two KPIs | ✅ |
| **C5** | **"Which parts are at risk of stockout?"** | `high_stockout` = `STOCKOUT_RISK = 'HIGH'` → **silently drops every CRITICAL part**. The worst parts are the ones it loses. | `CRITICAL OR HIGH` on the current snapshot, per the closed enum | `mfg:RiskLevel` = `{LOW, MEDIUM, HIGH, CRITICAL}` | ✅ |
| **C6** | "How much did we book, and how much did we earn?" | Risks using `ORDER_AMOUNT` for both, or swapping in `BOOKING_AMOUNT` | `total_revenue` and `total_bookings` as two distinct KPIs in two columns | `ea:Revenue notSameAs ea:Bookings` | SQL only |
| **C7** | **Entity resolution, 30 seconds.** Words that appear nowhere in the schema: "How's the **factory** in Chennai?" · "Which **DC**s are thin on cover?" · "Which **vendor**s are hurting us on quality?" · "Top **SKU**s at stockout risk" · "Revenue by **channel partner**" | Matches none of them — a metric view's synonym list covers its own fields, not the business vocabulary | `factory`→Plant, `DC`→Warehouse, `vendor`→Supplier, `SKU`→Part, `channel partner`→Dealer | `ea:aka` on 11 entity classes | ✅ (except the last) |

> **C5 is also a live repo finding, not just a demo.**
> [`metrics_inventory_snapshot.sql`](../metric_views/metrics_inventory_snapshot.sql)
> defines `high_stockout` as `STOCKOUT_RISK = 'HIGH'` and `restock_candidate` as
> `IN ('HIGH','MEDIUM')`, while the TTL declares four bands including `CRITICAL`.
> The semantic layer and the ontology currently disagree, and the ontology is
> right. Either widen both fields to include `CRITICAL`, or the S4 answer has to
> bypass the certified field — which is exactly the drift the ontology exists to
> catch. Fix before the demo; it's a two-line edit and a better story either way.

---

## Act D — S4 only: questions with no join path at fact grain

The five metric views share **no** join path across domains. These need
`kg_find_node` + `kg_neighbors` over `supplierSuppliesPart`, `partStockedAt`,
`plantHasLine`, `plantProducesModel`, `lineProducesModel`,
`campaignRunsOnChannel`, `campaignTargetsSegment`.

> ### What makes a question *only* S4-answerable
>
> Only two things, and it is worth being strict about them or S1/S2 will answer
> one of your "S4-only" questions live on the call:
>
> 1. **It needs `supplierSuppliesPart`.** That edge is the one built from
>    `supply_chain_analytics.dim_supplier_contract` (via
>    [`edge_sources.sql`](edge_sources.sql)), and **that table is not a data source in
>    S1 or S2 at all** — they carry 15 dims + the facts, no contract table. There is
>    no phrasing, no join, no instruction that gets them the sourcing relation. This
>    is a *data reachability* wall, not a comprehension one.
> 2. **It needs a declared non-path** (TTL §8: `Campaign → SalesOrder`,
>    `Plant → Part`, `Warehouse → Plant`). Only the ontology records the absence.
>
> **`plantHasLine`, `plantProducesModel`, `lineProducesModel`,
> `campaignRunsOnChannel` and `campaignTargetsSegment` do NOT qualify.** Every one
> of them is a distinct key pair off a *single* fact that S1 and S2 both have
> (`fact_production_execution` carries `PLANT_KEY`, `LINE_KEY` and `MODEL_KEY` on the
> same row; `fact_campaign_performance` carries `CAMPAIGN_KEY`, `CHANNEL_KEY` and
> `SEGMENT_KEY` on the same row), and both spaces have the dims for the names. A
> `SELECT DISTINCT` answers them. **D3 and D4 below are therefore mislabelled** —
> they are S4-*cleaner* (one tool call, typed, no fan-out risk), not S4-only. Demote
> them to warm-ups or drop them; the S4-only set is D1, D2, D5 and D6–D12.

| # | Ask this | S1–S3 | S4 | Proves | Safe |
| - | -------- | ----- | -- | ------ | ---- |
| **D1** | "Which suppliers feed the parts sitting in the Pune warehouse right now?" | Invents a join on a key the facts don't share, or gives up | `kg_find_node('Pune')` → `partStockedAt` (reverse) → `supplierSuppliesPart` (reverse) | 2-hop traversal, inverse properties | ✅ |
| **D2** | "If Supplier X goes down tomorrow, which warehouses and parts are exposed?" | Cannot answer | `supplierSuppliesPart` → `partStockedAt`, then `metrics_supplier_quality` for the PPM/COPQ **numbers** | Graph navigates, semantic layer measures | ✅ |
| **D3** | "Which vehicle models does the Chennai plant build, and on which lines?" | Guesses from name strings | `kg_neighbors('Plant', …, 'plantHasLine')` + `'plantProducesModel'` | Typed relations, declared inverses | ✅ |
| **D4** | "Which channels and segments does the Monsoon Festive campaign touch?" | Reads one fact table and misses the many-to-many | Two edge types off one campaign node | Entity→relationship instead of row scan | ✅ |
| **D5** | **"Which campaign drove the sales of model Baleno last quarter?"** | Fabricates an attribution join and answers with a number | **"There is no path."** No bridge table joins marketing spend to orders — a documented gap in TTL §8 | **Knowing what it cannot know.** The ontology turns a hallucination into an honest boundary | ✅ |

### D6–D10 — the sourcing relation S1/S2 cannot reach

All five are unanswerable in S1/S2 for the same structural reason: **the contract
table is not one of their data sources.** Their only route to a supplier–part
association is `fact_supplier_quality`, which is *inspection* grain — it means
"supplies this part **and** we have inspected it", **45 of 60 contracted pairs**.
That 25% shortfall is what makes every answer below wrong rather than missing.

| # | Ask this | S1–S3 | S4 | Proves | Safe |
| - | -------- | ----- | -- | ------ | ---- |
| **D6** | **"Which parts do we buy from a single supplier only?"** | Contract table absent → infers sole-source from inspection history. **Fails in both directions:** parts with an uninspected alternate look sole-sourced, and never-inspected parts (Blower Motor P0071, Headrest Guide P0088) look *unsourced* | Out-degree on `partSuppliedBy` = 1 over all 60 contracted pairs; P0055 correctly excluded (three suppliers) | Cardinality *is* the answer. A graph counts edges; a fact table counts events | ✅ |
| **D7** | **"Which parts are at critical stockout risk right now *and* have no alternate supplier?"** — the actual escalation list | S2 returns 0 rows (`= 'HIGH'` drops CRITICAL), and could not add the sourcing clause even if it got the band right | `is_current_snapshot` + closed enum `IN ('CRITICAL','HIGH')` + sole-source degree, then `Avg Days of Supply` for the runway | **All three layers in one answer**: semantic grain, ontology enum, graph cardinality | ✅ |
| **D8** | **"Are we holding stock of any part that no supplier is contracted to supply?"** | Cannot represent the question — with no contract set, "no supplier" is not a thing that can be false | Parts with a `partStockedAt` edge and **zero** `partSuppliedBy` edges | **Detecting a missing edge.** Only a closed relation makes absence meaningful | ✅ |
| **D9** | **"We're terminating our worst supplier on cost of poor quality. Which parts must we re-source, and which of them have no alternate?"** | Names a supplier (COPQ is governed in S2/S3), then stops — cannot list its parts, let alone their alternates | `MEASURE(Total Cost of Poor Quality)` picks the supplier → `supplierSuppliesPart` lists its parts → per-part degree splits re-sourceable from stranded | **The division of labour**: the semantic layer decides *who*, the graph decides *what breaks*. Neither alone gets to a decision | ✅ |
| **D10** | **"Rank our suppliers by how much of the warehouse network they reach."** | No path | 2-hop degree: `supplierSuppliesPart` → `partStockedAt`, distinct warehouses per supplier | Network exposure is a property of the *graph*, not of any row | ✅ |

### D11–D12 — declared non-paths that *feel* answerable

D5 is a safe decline because marketing-to-revenue attribution is obviously hard.
These two are the dangerous kind: both endpoints exist, so the fabrication is
plausible and nobody in the room will catch it.

| # | Ask this | S1–S3 | S4 | Proves | Safe |
| - | -------- | ----- | -- | ------ | ---- |
| **D11** | **"Which suppliers feed the Chennai plant?"** | Both halves exist (`plantProducesModel`, and a supplier–part guess off inspections) so it bridges them on whatever key looks joinable and answers with a **confident supplier list** | **"The middle hop does not exist."** No fact links a plant or line to the parts it consumes — TTL §8, `Plant → Part`. Offers what it *can* do: plant → models, and supplier → parts, separately | Declining a question where **both endpoints are reachable** is much harder than declining D5 — and much more valuable | ✅ |
| **D12** | **"Which warehouse supplies the Pune plant?"** | **String-matches the name.** There is a Pune warehouse and a Pune plant, so it answers "the Pune warehouse" — right-looking, entirely unjustified by any key | **"`dim_warehouse` has no plant reference."** TTL §8, `Warehouse → Plant`. Same-city naming is a coincidence, not a relation | The trap is the *name collision*. An ontology binds relations to keys, so it cannot be fooled by two facilities sharing a city | ⚠️ verify both facilities exist first |

**D5, D11 and D12 are the closing slides.** Every other question is "the ontology
gets it right". These three are "the ontology knows when there is no right answer"
— and D11/D12 make the point that the boundary holds even when a wrong answer
would have looked completely reasonable.

---

### Pre-flight for D6–D12

Each of these must return rows (or D12's pair must exist) or the question has no
punchline. Run them before the demo, not during it.

```sql
-- D6/D7/D9: sole-source parts must exist, and multi-sourced ones must too
SELECT p.node_name AS part, COUNT(DISTINCT e.subject_key) AS suppliers
FROM   gold_dev_analytics.ontology.kg_edges e
JOIN   gold_dev_analytics.ontology.kg_nodes p
       ON p.node_type = 'Part' AND p.node_key = e.object_key
WHERE  e.rel = 'supplierSuppliesPart'
GROUP  BY 1 ORDER BY suppliers, part;
-- expect: a block of suppliers=1 (D6's answer) and P0055 at 3. If everything is 1,
-- D6 is trivially "all of them" and D9's alternate/stranded split collapses.

-- D7: sole-source AND currently CRITICAL/HIGH — this is the money slide, it must be non-empty
WITH sole AS (
  SELECT object_key AS part_key FROM gold_dev_analytics.ontology.kg_edges
  WHERE rel = 'supplierSuppliesPart' GROUP BY 1 HAVING COUNT(DISTINCT subject_key) = 1)
SELECT i.`Part Name`, i.`Warehouse Name`, i.`Stockout Risk`
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot i
JOIN   gold_dev_analytics.dim.dim_part dp ON dp.PART_NAME = i.`Part Name`
JOIN   sole s ON CAST(dp.PART_KEY AS STRING) = s.part_key
WHERE  i.`Is Current Snapshot` = true AND i.`Stockout Risk` IN ('CRITICAL','HIGH');
-- if empty, fall back to D6 + D8 and drop D7 — do not soften the question to force a row

-- D8: stocked-but-unsourced orphans (may legitimately be zero — see below)
SELECT n.node_name AS part
FROM   gold_dev_analytics.ontology.kg_nodes n
WHERE  n.node_type = 'Part'
  AND  EXISTS (SELECT 1 FROM gold_dev_analytics.ontology.kg_edges e
               WHERE e.rel = 'partStockedAt' AND e.subject_key = n.node_key)
  AND  NOT EXISTS (SELECT 1 FROM gold_dev_analytics.ontology.kg_edges e
                   WHERE e.rel = 'supplierSuppliesPart' AND e.object_key = n.node_key);
-- zero rows is a PASS for the business and still a good demo: S4 says "none, and here
-- is how I know" while S1/S2 cannot distinguish that from "I didn't look"

-- D12: the name collision the trap depends on
SELECT 'plant' AS kind, PLANT_NAME     AS name FROM gold_dev_analytics.dim.dim_plant     WHERE PLANT_NAME     ILIKE '%Pune%'
UNION ALL
SELECT 'warehouse',      WAREHOUSE_NAME       FROM gold_dev_analytics.dim.dim_warehouse WHERE WAREHOUSE_NAME ILIKE '%Pune%';
-- need one of each. No pair sharing a city → pick another city, or drop D12.
```

---

## The 12-minute cut

**A1** (empty result read as good news) → **B4** (same question, three numbers) →
**C1** (asks instead of guessing) → **C5** (drops the CRITICAL parts) →
**D2** (blast radius: graph + measures together) → **D5** (declines to hallucinate).

**If the room is supply-chain rather than exec**, swap the last two for **D7**
(sole-source *and* critical — all three layers in one answer) → **D12** (declines
a question it could have answered plausibly by matching a city name).

## Scorecard — run every question through all four

| Dimension | What you're recording |
| --------- | --------------------- |
| Answerable at all | S4-only questions separate the graph from the rest |
| Correct measure | Right KPI for the words used |
| Correct grain / filter | Snapshot vs cumulative, period actually filtered |
| Correct unit | Percent not rendered as ₹; 0–100 vs 0–1 |
| Entity resolved | Business name, not surrogate key; synonym matched |
| Asked when ambiguous | S4's characteristic behaviour |
| **Deterministic** | Same answer across three paraphrases (B4) |
| Declined when unknowable | D5 |

S1's failure mode is `wrong-but-confident`. S4's is `asks a clarifying question`
or `says there is no path`. **That asymmetry is the entire pitch** — and it's
also why the Act 0 lifecycle table matters: S4's behaviour is only trustworthy
because it's generated from one file and asserted in CI.
