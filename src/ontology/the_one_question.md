# THE ONE QUESTION

One question. Four scenarios. Four materially different answers, every number verified
live against `gold_dev_analytics` on **2026-09-09** (warehouse `d2533a75c1bd9265`).

---

> # "How much stock is sitting in the Pune depot right now, which SKUs there are at risk of running out, who supplies them, and what are they costing us?"

A question any plant manager would ask on a Monday. It has **four clauses, and each one
breaks at a different layer** — so a single answer exposes all four scenarios at once.

| Clause | Layer it tests | The trap |
| ------ | -------------- | -------- |
| "how much stock … **right now**" | **S1 → S2** | Snapshot fact. Summing across dates inflates by the retention window. |
| "**Pune depot**" · "**SKUs**" · "**who supplies**" | **S3 → S4** | None of those three words appears anywhere in the schema. |
| "**at risk of running out**" | **S3 → S4** | `STOCKOUT_RISK` has four bands. The certified field is `'HIGH'` only. |
| "**who supplies them**" | **S4 only** | No join path at fact grain between inventory and supplier quality. |
| "what are they **costing** us" | **S2 → S3** (rollup) + **S3 → S4** (ambiguity) | `AVG` of a ratio; and "cost" has four valid senses. |

---

## The four answers, side by side

### S1 — Genie, no context

Raw facts, no descriptions, no synonyms, no instructions.

```sql
SELECT SUM(STOCK_VALUATION) AS stock_value, COUNT(*) AS parts_at_risk
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot
WHERE  STOCKOUT_RISK = 'HIGH'      -- drops CRITICAL
-- no snapshot-date filter         -- sums all 152 retained days
-- "depot"/"SKU" matched nothing; WAREHOUSE_KEY never resolved to Pune
-- "who supplies them" silently dropped from the answer
```

> **"Pune has ₹258.95 Cr of stock and 0 parts at risk."**

- **Stock value inflated 162.3×** — ₹258.95 Cr against a true ₹1.60 Cr, because all 152
  snapshot dates were summed as if they were additive.
- Warehouse never resolved. "Depot" matched no column, so the filter was dropped or guessed.
- **Two of the four clauses silently vanished.** No caveat, no hedge.
- One confident number a CFO would read aloud, and every part of it is wrong.

### S2 — Genie + context

Same raw tables, plus table/column descriptions, synonyms, and prose instructions.

```sql
SELECT SUM(STOCK_VALUATION) AS stock_value
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot
WHERE  SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM …)  -- ✅ prose worked
  AND  STOCKOUT_RISK = 'HIGH'                                      -- ❌ still drops CRITICAL
```

> **"Pune has ₹1.60 Cr of stock and 0 parts at risk."**

- ✅ **Grain fixed.** ₹1.60 Cr is correct — a table description said "point-in-time."
- ❌ Still `'HIGH'` only → still reports **zero parts at risk**.
- ❌ "Depot" and "SKU" still match nothing; `WAREHOUSE_KEY` comes back as a surrogate integer.
- ❌ Supplier clause still unanswerable.
- ⚠️ **And it is re-derived per phrasing.** Ask "value of stock at the Pune depot"
  tomorrow and the date filter may not come back — nothing enforces it.

### S3 — Genie agent + semantic layer

UC metric views, `MEASURE(...)`, certified `sql_snippets`, dim joins declared
`rely: at_most_one_match`, assertion job in CI.

```sql
SELECT `Warehouse Name`, MEASURE(`Total Stock Valuation`) AS stock_value
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  `Is Current Snapshot` = true      -- ✅ structural, not prose
  AND  `High Stockout` = true            -- ❌ certified field = 'HIGH' only
  AND  `Warehouse Name` ILIKE '%Pune%'   -- ✅ name, not surrogate key
GROUP BY 1
```

> **"Pune has ₹1.60 Cr of stock. No parts are at stockout risk."**
> *(verified: this query returns **zero rows**)*

- ✅ Grain is a **field**, not a filter it has to remember. Valuation is a certified measure.
- ✅ Dim join asserted non-fanning, so the number can't be inflated by a duplicate dim row.
- ✅ **Same SQL for every paraphrase** — this is the layer that makes answers repeatable.
- ❌ **The at-risk answer is confidently, reproducibly, *governed*ly wrong.** `High Stockout`
  is defined as `STOCKOUT_RISK = 'HIGH'`, and Pune has **0 HIGH and 3 CRITICAL**. The
  result is an **empty set reported as good news** — the most expensive failure shape there is.
- ❌ "Who supplies them" — no join path. S3 correctly declines. Honest, and useless.
- ❌ "Costing us" — answers with one governed measure and never mentions that it chose.

### S4 — Genie agent + semantic layer + ontology + knowledge graph

Everything in S3, plus the TTL as source of truth, generated grounding, and `kg_*`
traversal functions as agent tools.

> **"Pune RDC holds ₹1.60 Cr of stock. 3 parts are CRITICAL — below safety stock with
> 3–4 days of cover:**
>
> | Part | On hand | Safety stock | Days of supply | Value |
> | - | - | - | - | - |
> | **Blower Motor** | 50 | 165 | **3.0** | ₹56,500 |
> | **Clutch Plate** | 78 | 171 | 4.0 | ₹1,46,406 |
> | **Grommet** | 127 | 258 | 4.0 | ₹85,471 |
>
> **Suppliers:** Clutch Plate ← **Shivalik Autotech** · Grommet ← **Palar Rubber Industries**.
> **Blower Motor has no supplier on record** — zero incoming inspections, so there is no
> quality history and no vendor to escalate to. That is a gap, not a zero.
>
> On **"costing us"** — that could mean cost of poor quality on those suppliers, the value
> of the stock itself, campaign spend, or order discount. **Which did you mean?"**

```sql
-- 1. at-risk parts: the closed enum from the ontology, not the certified boolean
SELECT `Part Name`, `Stockout Risk`, MEASURE(`Total Stock Valuation`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  `Is Current Snapshot` = true
  AND  `Stockout Risk` IN ('CRITICAL','HIGH')   -- ✅ full band, per owl:oneOf
  AND  `Warehouse Name` ILIKE '%Pune%'          -- ✅ "depot" → Warehouse, via ea:aka
GROUP BY 1, 2;

-- 2. who supplies them: the graph, because no fact joins these two domains
SELECT DISTINCT s.node_name AS supplier, p.node_name AS part
FROM      gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s
WHERE p.node_name IN ('Blower Motor','Clutch Plate','Grommet');

-- 3. then, and only then, the KPI — from the governed layer, on exactly those suppliers
SELECT `Supplier Name`, MEASURE(PPM), MEASURE(`Total Cost of Poor Quality`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_supplier_quality
WHERE  `Supplier Name` IN ('Shivalik Autotech','Palar Rubber Industries')
GROUP BY 1;
```

**Every mechanism in one answer:** `ea:aka "depot"` resolved the word · `mfg:RiskLevel`
closed with `owl:oneOf {LOW, MEDIUM, HIGH, CRITICAL}` found the 3 parts · two graph hops
found the vendors · the metric views supplied the numbers · `ea:Cost disambiguatesTo`
(4 senses) stopped it from guessing · and the missing Blower Motor edge is reported as a
gap instead of an omission.

---

## The scorecard

| | Stock value | Parts at risk | Who supplies them | "Costing us" |
| - | - | - | - | - |
| **S1** no context | **₹258.95 Cr** (162× inflated) | 0 (HIGH only, wrong warehouse) | silently dropped | guessed |
| **S2** + context | ✅ ₹1.60 Cr *(if it obeys the prose)* | **0** (HIGH only) | silently dropped | guessed |
| **S3** + semantic layer | ✅ ₹1.60 Cr, certified & repeatable | **0** — *"nothing at risk"* | no path; declines | guessed, confidently |
| **S4** + ontology & KG | ✅ ₹1.60 Cr, certified | **3 CRITICAL**, 3–4 days cover | **2 suppliers + 1 named gap** | **asks** |

**S1 and S2 hand you a number. S3 hands you a number you can trust to be computed the
same way tomorrow. S4 is the first one that answers the question that was actually
asked — and the first one that admits what it can't.**

---

## The two beats that need one extra prompt

The single question above covers S1→S2, S3→S4, and S4-only. Two axes need one follow-up
each — same question, asked differently.

### Beat 1 — S2 → S3: ask it three ways *(the semantic-layer proof)*

Ask the *same* question in three fresh sessions:

1. "…what are they **costing us**?"
2. "…how bad is their **defect rate**?"
3. "…which of those **vendors is hurting us most on quality**?"

**S2 re-derives the rollup from prose each time.** On Shivalik Autotech and Palar Rubber Industries the two
formulas disagree — verified:

| Supplier | S2: `AVG(PPM_LEVEL)` | S3: `MEASURE(PPM)` weighted | COPQ |
| - | - | - | - |
| **Shivalik Autotech** | 14,522.5 | **18,470.8** *(understated 27%)* | **₹8.18 Lakh** |
| **Palar Rubber Industries** | 22,310.7 | 20,613.9 *(overstated 8%)* | ₹4.33 Lakh |

**This flips the decision.** On S2's averaged PPM, Palar Rubber Industries looks like the worse
vendor by a wide margin — 22,311 vs 14,523. On the correct spend-weighted rollup the gap
nearly closes, and on cost of poor quality **Shivalik Autotech is nearly 2× the bigger problem**
(₹8.18 Lakh vs ₹4.33 Lakh). S2 sends you to escalate the wrong supplier.

S3 returns `MEASURE(PPM)` on all three phrasings. Same SQL, same number, same ranking.
*Nobody argues with "same question, same number, every time."*

### Beat 2 — Genie code vs. Genie agent: ask it again next quarter

> **"Same question, next quarter. The at-risk count changed. Was that the data, or did
> someone edit the definition?"**

This is the one thing a UI-configured Genie space **cannot answer at any level of context**
— it isn't about accuracy, it's about lifecycle.

| Ask | Genie code (UI) | This agent |
| - | - | - |
| Did the definition change, and who changed it? | No answer — UI edits leave no diff | `git log src/metric_views/` |
| Prove PPM is still weighted, not averaged | Ask it and hope | `./deploy.sh test-metrics` → [`assert_kpi_formulas.sql`](../tests/assert_kpi_formulas.sql) fails the job |
| Ship the identical agent to prod | Re-type it by hand | `./deploy.sh deploy --target prod` |
| A KPI was renamed in 3 places — did they miss one? | Manual audit | Edit the TTL, `regen-tags`, 6 artifacts regenerate |
| Is a dim join fanning out and inflating every KPI? | Unknowable | [`assert_dim_uniqueness.sql`](../tests/assert_dim_uniqueness.sql) tests exactly that |

**Live proof, not theory.** The deployed `supply_chain_analytics` schema currently holds
three metric views the repo doesn't define (`metrics_inventory_transaction`,
`metrics_restock_request`, `metrics_supplier_delivery`), and the deployed
`metrics_inventory_snapshot` uses Title Case measure names while
[the repo `.sql`](../metric_views/metrics_inventory_snapshot.sql) uses snake_case. Someone
edited outside the bundle. Run `python src/ontology/verify_bindings.py` on stage and let
it find the drift — **that is the answer to Beat 2.**

---

## Why this question and not another

- **Every number is live and non-NULL.** Inventory and supplier quality are the two fully
  loaded domains. Revenue (`ORDER_AMOUNT`, `STATUS`) and marketing (`LEADS`, `ROAS`) are
  still NULL in `gold_dev_analytics`, so any revenue/ROAS question differentiates only on
  generated SQL, not on a number. This question deliberately avoids both.
- **The S3→S4 flip is an empty result, not a wrong number.** "Nothing is at risk" is the
  failure nobody investigates. That asymmetry is the whole pitch.
- **It is a real finding, not a staged one.** `high_stockout` is `= 'HIGH'` while the
  ontology declares four bands. Across all warehouses S3 finds **20** at-risk parts and
  S4 finds **35** — a **43% undercount that loses the worst 15**. The semantic layer and
  the ontology genuinely disagree, and the ontology is right.

> **Do not fix `high_stockout` before the demo.** It is the strongest evidence in the deck.
> Fix it after, and the fix itself becomes Beat 2's git-log story.

### Three things to check the morning of

```sql
-- 1. Pune still has CRITICAL parts and no HIGH ones (the whole flip depends on this)
SELECT `Warehouse Name`, `Stockout Risk`, MEASURE(`Snapshot Row Count`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  `Is Current Snapshot` = true AND `Warehouse Name` ILIKE '%Pune%'
GROUP BY 1, 2 ORDER BY 2;
-- expect: CRITICAL 3, MEDIUM/LOW some, HIGH absent

-- 2. the 162× inflation is still there
SELECT SUM(STOCK_VALUATION) FILTER (WHERE SNAPSHOT_DATE_KEY = (SELECT MAX(SNAPSHOT_DATE_KEY) FROM gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot)) AS cur,
       SUM(STOCK_VALUATION) AS all_dates
FROM   gold_dev_analytics.supply_chain_analytics.fact_inventory_snapshot f
JOIN   gold_dev_analytics.dim.dim_warehouse w ON w.WAREHOUSE_KEY = f.WAREHOUSE_KEY
WHERE  w.WAREHOUSE_NAME = 'Pune RDC';
-- expect: 15,951,591 vs 2,589,477,910

-- 3. the graph still reaches the suppliers
SELECT DISTINCT s.node_name, p.node_name
FROM      gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s
WHERE p.node_name IN ('Blower Motor','Clutch Plate','Grommet');
-- expect: Shivalik Autotech/Clutch Plate, Palar Rubber Industries/Grommet, no Blower Motor row
```

If Pune ever loses its CRITICAL-without-HIGH shape, swap in **Ahmedabad RDC** (1 HIGH,
4 CRITICAL) — same story, slightly weaker because S3 returns 1 row instead of none.

---

*Companion files: [`scenario_questions.md`](scenario_questions.md) — the eight-question
set if you have more than one slide. [`demo_questions.md`](demo_questions.md) — long-form
narrative.*
