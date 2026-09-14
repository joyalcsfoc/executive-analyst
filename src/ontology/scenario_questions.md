# Four-Scenario Comparison — verified question set

Every number below was run against `gold_dev_analytics` on **2026-09-09** via warehouse
`d2533a75c1bd9265`. Each question is chosen because the answer **flips at exactly one
boundary**, and the flip is visible in a number a room can read — not just in the SQL.

The long-form narrative version of this is [`demo_questions.md`](demo_questions.md).
This file is the runnable set: ask, record, compare.

---

## Setup — the four spaces you actually need

Only **S4 exists today**. [`src/executive_analyst.geniespace.json`](../executive_analyst.geniespace.json)
deploys all layers at once. To compare, clone it three times and strip:

| | Space contents | Strip from the JSON |
| - | - | - |
| **S1** | 5 raw facts + `dim.*`. Nothing else. | `metric_views`, `instructions.*`, all `description` / `synonyms`, `sample_questions` |
| **S2** | S1 + table/column descriptions, synonyms, prose instructions | `metric_views`, `instructions.sql_functions`, `sql_snippets`, and the `## Ontology grounding` block from `text_instructions` |
| **S3** | S2 + the 5 metric views, `sql_snippets`, dim joins with `rely` | `instructions.sql_functions` and the `## Ontology grounding` block |
| **S4** | ship as-is | — |

The only difference between S3 and S4 is the generated `## Ontology grounding` block plus
the two `kg_*` functions. That is deliberate: **S3→S4 is one editable section**, so the
comparison is honest.

---

## Q1 — Agent vs. Genie-in-the-UI (no data required)

> **"Our CFO says the discount number moved last quarter. Show me who changed the
> definition, when, prove the current definition is still correct, and ship the same
> answer to the prod workspace."**

This is the one question a UI-configured Genie space **cannot answer at all**, at any
level of context. It is not about accuracy — it is about lifecycle.

| | Response |
| - | - |
| **Genie code (UI)** | Answers the *number*. On the other four clauses: nothing. UI edits leave no diff, no test, no promotion path. |
| **Genie agent (this repo)** | `git log src/metric_views/metrics_sales_order.sql` → author + timestamp. `./deploy.sh test-metrics` → [`assert_kpi_formulas.sql`](../tests/assert_kpi_formulas.sql) re-derives `discount_percent` from the raw fact and fails the job if it drifted. `./deploy.sh deploy --target prod` → same bundle, `gold` catalog. |

**Ask the room these five in sequence** — each is a row the UI cannot fill:

| Ask | UI space | This agent |
| - | - | - |
| Who changed the revenue definition, and when? | No answer | `git log src/metric_views/` |
| Prove PPM is still weighted, not averaged | Ask it and hope | `assert_kpi_formulas` fails the job |
| Ship the identical agent to prod | Re-type it by hand | `./deploy.sh deploy --target prod` |
| A KPI was renamed in 3 places — did they miss one? | Manual audit | Edit the TTL, `regen-tags`, 6 artifacts regenerate |
| Is a dim join silently fanning out and inflating every KPI? | Unknowable | [`assert_dim_uniqueness.sql`](../tests/assert_dim_uniqueness.sql) tests exactly that |
| Can it call a tool, not just write `SELECT`s? | No | `kg_find_node` / `kg_neighbors` as `sql_functions` |

**Live proof this is not theoretical.** The deployed `supply_chain_analytics` schema
currently contains three metric views the repo does not define — `metrics_inventory_transaction`,
`metrics_restock_request`, `metrics_supplier_delivery` — and the deployed
`metrics_inventory_snapshot` uses Title Case measure names (`Total Stock Valuation`)
while [the repo `.sql`](../metric_views/metrics_inventory_snapshot.sql) uses snake_case
(`total_stock_valuation`). Someone edited outside the bundle. That drift is *the answer
to Q1*: run `python src/ontology/verify_bindings.py` on stage and let it find the gap.

---

## Q2 — S1 → S2: context stops the confident wrong answer

> **"What is our total inventory value right now?"**

| | Response | Verified |
| - | - | - |
| **S1** no context | `SUM(STOCK_VALUATION)` with no date filter → **₹1,28,564.69 Cr** | 152 snapshot dates summed together |
| **S2** + context | Table description says point-in-time → filters latest `SNAPSHOT_DATE_KEY` → **₹928.68 Cr** | Correct |
| **S3** + semantic layer | `MEASURE(\`Total Stock Valuation\`) WHERE \`Is Current Snapshot\` = true` → **₹928.68 Cr** — grain is now a *field*, not a filter it has to remember | Correct, and repeatable |
| **S4** + ontology | Same. `mfg:StockPosition` carries `ea:grainTag "snapshot"`. | Correct |

**The number to say out loud: S1 is inflated 138.4×.** Not wrong by a rounding error —
wrong by two orders of magnitude, delivered with total confidence, in a format a CFO
would read aloud. That is the S1 failure mode in one figure.

Flips at: **S1→S2**. Made structural at S3.

---

## Q3 — S1 → S2: the silent scale error

> **"How many production runs missed the 70% OEE standard?"**

`OEE_PCT` is stored 0–100 (verified: min 0.00, max 120.00).

| | Response | Verified |
| - | - | - |
| **S1** | `WHERE OEE_PCT < 0.7` — assumes a 0–1 ratio → **720 runs** | Undercounts by 139 |
| **S2** | Column description states 0–100 → `< 70` → **859 runs** | Correct |
| **S3** | `oee_below_70` — the threshold is a governed field, not a literal re-derived per phrasing | Correct, deterministic |
| **S4** | Same, plus `ea:OEE` states the 0–100 scale in the ontology and `notSameAs ea:InventoryTurnover` | Correct |

S1 loses **16% of the failing runs** and reports the rest as the complete list. Note the
subtlety worth naming on stage: because 720 rows genuinely sit below 0.7, the wrong query
returns a *plausible non-empty result*. Nothing looks broken. That is why prose context is
worth paying for before you get to governance.

Flips at: **S1→S2**.

---

## Q4 — S2 → S3: prose is advisory, the semantic layer is enforced

> **"What is our supplier defect rate in PPM?"**

| | Response | Verified |
| - | - | - |
| **S1** | `SUM(PPM_LEVEL)` → **14,720,705 PPM** — i.e. "1,472% of parts are defective" | Nonsense |
| **S2** | Prose says roll up as `SUM(DEFECT_QTY)/SUM(INSPECTED_QTY)*1e6` → correct **when it follows the prose**. Often lands on `AVG(PPM_LEVEL)` → **21,905.81** | Off by +715.8 PPM (3.4%) |
| **S3** | `MEASURE(PPM)` → **21,190.02** | Correct, every time |
| **S4** | Same measure; `ea:PPM` binds it and forbids the alternative | Correct |

**Then run the determinism test — this is the actual S3 slide.** Ask the same thing three
ways, in three fresh sessions:

1. "supplier defect rate in PPM"
2. "parts per million rejects by vendor"
3. "which suppliers are worst on incoming quality?"

- **S2** re-derives the formula each time from prose. Expect 2–3 different SQL shapes and
  the `AVG` vs weighted split above — a **3.4% swing that changes the supplier ranking**.
- **S3** returns `MEASURE(PPM)` on all three. Same SQL, same number.

Screenshot the three S2 answers next to the one S3 answer. Nobody argues with *"same
question, same number, every time."*

Flips at: **S2→S3** (determinism). S1's number is the comic relief.

---

## Q5 — S3 → S4: the ontology decides what the *word* means ★

> **"Which parts in the Pune depot are at risk of running out?"**

This is the strongest question in the set. Both S3 and S4 are governed, certified, and
repeatable. They return **opposite answers**, and S3's is the dangerous one.

| | Response | Verified |
| - | - | - |
| **S1** | "depot" matches nothing; `WAREHOUSE_KEY` never resolves to Pune; no snapshot filter → wrong warehouse (or all), wrong risk band | — |
| **S2** | Snapshot filter comes right from prose. "depot" still matches nothing — the word appears nowhere in the schema | — |
| **S3** | The certified field: `WHERE \`High Stockout\` = true AND \`Is Current Snapshot\` = true AND \`Warehouse Name\` ILIKE '%Pune%'` → **zero rows.** Reported as *"no parts at Pune are at stockout risk."* | **Empty result set** |
| **S4** | `mfg:RiskLevel` is closed with `owl:oneOf {LOW, MEDIUM, HIGH, CRITICAL}`, so "at risk" is `IN ('CRITICAL','HIGH')` → **3 CRITICAL parts, ₹2.88 Lakh at Pune RDC** | **3 rows** |

**S3 says "nothing is at risk." S4 finds 3 parts already past critical.** The certified
field `High Stockout` is defined as `STOCKOUT_RISK = 'HIGH'` — and Pune RDC currently has
**0 HIGH and 3 CRITICAL**. The semantic layer is confidently, reproducibly, *governed*ly
wrong, and it fails as an **empty result read as good news** — the most expensive failure
shape there is.

**Scale it up for the second beat.** Ask the same question with no warehouse filter:

| | At-risk parts, all warehouses, current snapshot |
| - | - |
| **S3** `High Stockout = true` | **20** |
| **S4** `Stockout Risk IN ('CRITICAL','HIGH')` | **35** |

S3 misses **15 of 35 — a 43% undercount, and it loses the worst 15.** Current bands:
`CRITICAL 15 · HIGH 20 · MEDIUM 39 · LOW 205`.

> **This is a live repo finding, not a staged demo.** The metric view and the ontology
> disagree, and the ontology is right. Either widen `high_stockout` to include `CRITICAL`,
> or S4 must bypass the certified field — which is exactly the drift the ontology exists
> to catch. **Do not fix it before the demo.** It is the best evidence in the deck.

Flips at: **S3→S4**, twice — the closed enum *and* `ea:aka "depot"` → `mfg:Warehouse`.

---

## Q6 — S3 → S4: asking beats answering

> **"What did we spend last month?"**

| | Response |
| - | - |
| **S1 / S2** | Picks a spend-shaped column and answers. No signal that a choice was made. |
| **S3** | Picks one *governed* measure — probably `MEASURE(total_spend)` — and answers with total confidence. **Correctly computed, wrong question answered.** A metric view governs *how* a KPI is computed; it cannot tell you *which* KPI was meant. |
| **S4** | **Stops and asks:** *"'spend' could mean campaign spend, cost per lead, cost of poor quality, or discount given away on orders — which did you mean?"* |

Backed by `ea:Cost disambiguatesTo ea:CampaignSpend, ea:CostPerLead, ea:COPQ, ea:Discount`
— four senses across three domains, declared in the TTL and generated into the space
instructions.

**Two more from the same mechanism**, ask whichever fits the room:

| Ask | S3 | S4 | Backing |
| - | - | - | - |
| "Which plants are most efficient?" | Silently defaults to OEE | Asks: production OEE, or inventory turnover? | `ea:Efficiency disambiguatesTo` |
| "How's our turnover?" | Picks whichever it saw first | Surfaces the collision — "turnover" is an `aka` for **both** `ea:Revenue` (topline) and `ea:InventoryTurnover` (stock turns) → asks | `ea:aka` collision across two KPIs |

The turnover one is the sharper demo: the same English word is a synonym for two KPIs in
two different domains with two different units. No amount of per-view synonym curation
finds that, because each metric view only knows its own fields. **Only a shared vocabulary
sees the collision.**

Flips at: **S3→S4**. S1/S2/S3 all answer; only S4 asks.

---

## Q7 — S4 only: questions with no join path at fact grain

> **"Which suppliers feed the parts sitting in the Pune warehouse right now, and how are
> they performing on quality?"**

The five metric views share **no** join path across domains — the space instructions
explicitly say *"Never JOIN or UNION across domains."* So this is unanswerable below S4.

| | Response | Verified |
| - | - | - |
| **S1** | Invents a join on a key the facts do not share, or returns a wrong-grain cross product | — |
| **S2** | Same, or gives up | — |
| **S3** | Correctly **declines** — no path exists, and the instructions forbid inventing one. Honest, and useless. | — |
| **S4** | `kg_find_node('Pune')` → `partStockedAt` (reverse) → `supplierSuppliesPart` (reverse) → **12 parts, 11 suppliers** — then `MEASURE(PPM)` and `MEASURE(\`Total Cost of Poor Quality\`)` on exactly those 11 | **12 parts → 11 suppliers** |

The division of labour is the point: **the graph navigates, the semantic layer measures.**
The KG carries structure only — no KPI math ever moves into it.

```sql
-- hop 1+2: structure
SELECT DISTINCT s.node_name AS supplier, p.node_name AS part
FROM      gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s;

-- then, and only then: the numbers, from the governed layer
SELECT `Supplier Name`, MEASURE(PPM), MEASURE(`Total Cost of Poor Quality`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_supplier_quality
WHERE  `Supplier Name` IN ( /* the 11 from above */ )
GROUP BY 1 ORDER BY 2 DESC;
```

**Variants, all verified live** (edge counts in parentheses):

| Ask | Traversal | Edges |
| - | - | - |
| "If Supplier X goes down tomorrow, which warehouses and parts are exposed?" | `supplierSuppliesPart` → `partStockedAt` | 45 → 279 |
| "Which vehicle models does the Gurgaon plant build, and on which lines?" | `plantHasLine` + `plantProducesModel` | 6 + 12 |
| "Which channels and segments does campaign X touch?" | `campaignRunsOnChannel` + `campaignTargetsSegment` | 1,030 + 205 |

Flips at: **S3→S4** — but note the honest version: S3 declines correctly. The
differentiator is not "S3 lies," it is **"S3 cannot, S4 can."**

---

## Q8 — the closing question: knowing what it cannot know

> **"Which campaign drove the sales of the Baleno last quarter?"**

| | Response |
| - | - |
| **S1 / S2** | Fabricates an attribution join and answers with a number. There is no such join. |
| **S3** | Declines, but cannot say *why* — only that no measure spans both domains. |
| **S4** | **"There is no path."** No bridge table joins marketing spend to sales orders. Documented in [`exec_analyst.ttl`](exec_analyst.ttl) §8 as a known gap, alongside `Plant → Part` and `Warehouse → Plant`. The ontology models the *absence* of a relation as explicitly as it models the presence of one. |

Every other question in this set is *"the ontology gets it right."* **Q8 is "the ontology
knows when there is no right answer"** — and it is the only one of the four scenarios that
can say so with a citation.

---

## Scorecard — run all eight through all four spaces

| Dimension | What you record | Question |
| - | - | - |
| Lifecycle / auditability | Can you prove who changed a definition? | Q1 |
| Correct grain | Snapshot vs cumulative | Q2 |
| Correct unit / scale | 0–100 vs 0–1; percent not rendered as ₹ | Q3 |
| Correct rollup | Weighted ratio, not `AVG` of ratios | Q4 |
| **Deterministic** | Same answer across three paraphrases | Q4 |
| Entity resolved | "depot" / "SKU" / "vendor" / "factory" matched | Q5, Q7 |
| **Complete enum** | `CRITICAL` not silently dropped | **Q5** |
| Asked when ambiguous | Clarifying question, not a confident default | Q6 |
| Answerable at all | Cross-domain traversal | Q7 |
| Declined when unknowable | Named the gap, cited it | Q8 |

**S1's failure mode is `wrong-but-confident`. S4's is `asks a clarifying question` or
`says there is no path`. That asymmetry is the entire pitch** — and S4's behaviour is only
trustworthy because it is generated from one TTL file and asserted in CI.

---

## The 10-minute cut

**Q1** (git log vs. no answer) → **Q2** (inflated 138×) → **Q4** (three paraphrases, three
numbers) → **Q5** (S3 says nothing at risk; S4 finds 3 CRITICAL) → **Q7** (graph navigates,
metrics measure) → **Q8** (declines to hallucinate).

If you get **one** question: **Q5.** It is the only one where two *governed* layers
disagree, the ontology is provably right, the failure is an empty result read as good news,
and every number is live in `gold_dev_analytics` today.

---

## Data reality — read before demoing (verified 2026-09-09)

| Domain | Status | Data ends |
| - | - | - |
| Inventory | ✅ full | `20260904` |
| Supplier quality | ✅ full | `20260904` |
| Manufacturing | ✅ full | `20261103` (future-dated) |
| Knowledge graph | ✅ 11 classes, 7 relations, 1,589 edges | current snapshot |
| Revenue | ⚠️ `ORDER_AMOUNT` and `STATUS` are **NULL** on all 1,100 rows. `BOOKING_AMOUNT` works (₹10.93 Cr). | `20261115` |
| Marketing | ⚠️ `LEADS` and `ROAS` are **NULL**. `ACTUAL_SPEND` (₹90.87 Cr) and `CONVERSIONS` (38,056) work. | `20260801` |

**Every question Q1–Q8 above runs on demo-safe data.** Revenue and marketing are avoided
on purpose — that is why Q4 uses PPM rather than ROAS, and Q2 uses inventory valuation
rather than revenue.

Three repo notes worth knowing on stage:

1. **TTL §8 is stale on `MODEL_KEY`.** It says `fact_sales_order.MODEL_KEY` is `-1` on all
   rows; it now has **13 distinct values**. The `dealerSellsModel` edge is still commented
   out in §7 and can likely be re-enabled — `ORDER_AMOUNT`/`STATUS` are still null, but the
   key is not.
2. **A stale binding in the space config.** `sql_snippets.measures` references
   `MEASURE(ppm)` while the deployed view exposes `PPM`. Run `verify_bindings.py`.
3. **Do not run `./deploy.sh apply-metrics`** with the metric-view CREATE tasks enabled
   before the demo. The repo `.sql` would rename every supply-chain measure back to
   snake_case and break the S3/S4 SQL above. See TTL §7.1.

### Reproduce every number in this file

```sql
-- Q2: 138.4× inflation
SELECT SUM(STOCK_VALUATION) FILTER (WHERE SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot)) AS current_day,
       SUM(STOCK_VALUATION) AS all_152_dates
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot;

-- Q3: 720 vs 859
SELECT COUNT(*) FILTER (WHERE OEE_PCT < 0.7) AS s1_wrong_scale,
       COUNT(*) FILTER (WHERE OEE_PCT < 70)  AS correct
FROM   gold_dev_analytics.manufacturing_analytics.fact_production_execution;

-- Q4: 14.7M vs 21,905.81 vs 21,190.02
SELECT SUM(PPM_LEVEL) AS s1, AVG(PPM_LEVEL) AS s2_drift,
       SUM(DEFECT_QTY)/NULLIF(SUM(INSPECTED_QTY),0)*1e6 AS correct
FROM   gold_dev_analytics.supply_chain_analytics.fact_supplier_quality;

-- Q5: 20 vs 35, and Pune 0 vs 3
SELECT MEASURE(`Snapshot Row Count`) FILTER (WHERE `High Stockout` = true) AS s3,
       MEASURE(`Snapshot Row Count`) FILTER (WHERE `Stockout Risk` IN ('CRITICAL','HIGH')) AS s4
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  `Is Current Snapshot` = true;

-- Q7: 12 parts, 11 suppliers
SELECT COUNT(DISTINCT p.node_key) AS parts, COUNT(DISTINCT s.node_name) AS suppliers
FROM      gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s;
```
