# Three questions, three Genie spaces

Purpose: prove *why* the semantic layer and the ontology/KG are worth building, by asking the
same three questions of all three deployed spaces and comparing the answers.

## What each space actually has

| | `automotive-sales-manufacturing` (**A**) | `manufacturing-sales` (**B**) | `executive-analyst` (**C**) |
| - | - | - | - |
| Catalog | `gold_dev_analytics` | `gold_dev` dims + `gold_dev_analytics` facts | `gold_dev_analytics` |
| Data sources | 15 dims + 4 facts | 15 dims + 5 facts + **5 metric views** | **5 facts + 5 metric views** (no dims) |
| Table/column descriptions | none | none | on every table + column |
| Column synonyms | none | none | 3 per key column |
| Text instructions | **none** | 1 block (routing, clarification, empty-period, formatting) | same block **+ generated ontology grounding** |
| Certified `sql_snippets` | none | none | 8 measures + 4 filters |
| SQL functions | none | none | `kg_find_node`, `kg_neighbors` |
| Sample questions | none | 3 | 18 |

So: **A = raw tables. B = A + semantic layer. C = B + ontology + knowledge graph.** Each question
below moves exactly one of those two boundaries.

### Two fairness constraints (do not violate these or the comparison is worthless)

1. **No revenue or marketing questions.** A has no `fact_sales_order` at all, and `ORDER_AMOUNT`,
   `LEADS`, `ROAS` are still NULL in `gold_dev_analytics`. A revenue question fails A for the wrong
   reason. All three questions below stay in inventory / supplier quality / production, which are
   fully loaded.
2. **No pure ambiguity questions** ("what did we spend last month?", "which plants are most
   efficient?"). B and C carry the *same* clarification prose, so those separate B from A but not
   C from B. They are already covered in [`benchmark_questions.md`](benchmark_questions.md).

---

## Q1 — "Rank our suppliers by defect rate (PPM) — who is worst on quality?"

**Isolates: the semantic layer.** (A **wrong ranking** · B right · C right)

`PPM_LEVEL` sits on `fact_supplier_quality` at inspection grain, and averaging it is the obvious
move — it is a rate, one per row, already named PPM. But PPM is a **weighted ratio**: the certified
rollup is `SUM(DEFECT_QTY) / SUM(INSPECTED_QTY) * 1e6`. **No column name tells you that.** The
correct formula exists only as a definition someone wrote down, which is exactly what a semantic
layer is.

| | Expected answer | Why |
| - | - | - |
| **A** | Palar Rubber Industries (**22,310**) ranked far worse than Shivalik Autotech (**14,523**) | No metric view to route to → hand-rolls `AVG(PPM_LEVEL)`, which weights a 10-unit inspection the same as a 10,000-unit one |
| **B** | 013 = **18,471**, 015 = **20,614** — gap nearly closed | `MEASURE(ppm)` on `metrics_supplier_quality`, weighted by inspected qty |
| **C** | Same, and volunteers COPQ alongside: **013 = ₹8.18 Lakh vs 015 = ₹4.33 Lakh** | Same measure, plus the `ea:COPQ` binding makes cost-of-quality the natural companion metric |

**The ranking flips the decision.** On A's averaged PPM you escalate Palar Rubber Industries. On the correct
weighted rollup 013 is understated by **27%**, and on cost of poor quality **013 is nearly 2× the
bigger problem**. A sends you to the wrong vendor with a confident number.

**Then test repeatability**, which is the semantic layer's actual product. Ask the same thing three
ways in three *fresh* sessions per space:

1. "…how bad is their **defect rate**?"
2. "…which **vendors are hurting us most on quality**?"
3. "…what are those suppliers **costing us**?"

A re-derives the formula from scratch each time and can land on `AVG`, `SUM`, or a per-part average
depending on phrasing. B and C return `MEASURE(ppm)` on all three — same SQL, same number, same
ranking. *Nobody argues with "same question, same number, every time."*

> **If A also gets the weighted rollup right,** don't stretch for another accuracy question — the
> honest finding is that the base model handles single-metric math well, and the semantic layer's
> case rests on repeatability (above) and lifecycle (Beat 2 in
> [`the_one_question.md`](the_one_question.md)), not on one lucky answer.

### Retired: the snapshot-grain question

*"How much inventory value are we holding in the Pune warehouse right now?"* was the original Q1.
**It no longer differentiates** — run 2026-09-10, all three spaces returned **₹1.60 Cr**. The
`SNAPSHOT_DATE_KEY` column name plus "right now" is enough for the base model to filter to the
latest snapshot unaided, so the 162× inflation (₹258.95 Cr) documented in
[`the_one_question.md`](the_one_question.md) did not reproduce on A. Only cosmetic differences
remained: one space formatted the figure as "₹15.95 million" instead of the mandated `₹X.XX Cr`,
and only some labelled the snapshot date. Not a demo slide. Keep the question as a **regression
smoke test**, not as evidence.

---

## Q2 — "Which SKUs at the Pune depot are at risk of running out right now?"

**Isolates: the ontology.** (A wrong · B **confidently, reproducibly, governed-ly wrong** · C right)

Two independent traps, both vocabulary:

- "SKU" and "depot" appear nowhere in the schema. Only C has `ea:aka "SKU"` on `mfg:Part` and
  `ea:aka "DC", "depot"` on `mfg:Warehouse`.
- `STOCKOUT_RISK` has **four** bands (`LOW`/`MEDIUM`/`HIGH`/`CRITICAL`), closed with `owl:oneOf` in
  the TTL. The certified filter `high_stockout` is `= 'HIGH'` only. **Pune has 0 HIGH and 3 CRITICAL.**

| | Expected answer | Why |
| - | - | - |
| **A** | garbage, or "0 at risk" | "depot"/"SKU" match nothing; `WAREHOUSE_KEY` stays a surrogate int; guesses `= 'HIGH'`; no snapshot filter |
| **B** | **"No parts are at stockout risk at Pune."** — *zero rows returned as good news* | `high_stockout = true` is certified, repeatable, and **excludes CRITICAL**. This is the expensive failure: nobody investigates an empty result |
| **C** | **3 CRITICAL parts** — Blower Motor, Clutch Plate, Grommet — each below safety stock with 3–4 days of cover | `ea:aka` resolved "depot" and "SKU"; `owl:oneOf` supplied the full band → `Stockout Risk IN ('CRITICAL','HIGH')` |

**This is the strongest question in the set** because the failure is silent. B is not sloppy — it is
*governed*, and still wrong, because governance without a vocabulary certifies whatever the first
author typed. Across all warehouses the gap is **20 parts (B) vs 35 (C) — a 43% undercount that
loses the worst 15.**

> Do not "fix" `high_stockout` to include CRITICAL before running this comparison. The disagreement
> between the semantic layer and the ontology is the finding. Fix it after, and the fix becomes the
> lifecycle story (`git log src/metric_views/`).

---

## Q3 — "Which suppliers feed the parts sitting in the Pune warehouse right now, and if one of them goes down tomorrow, which other warehouses and parts are exposed?"

**Isolates: the knowledge graph.** (A fabricates · B declines · C answers)

There is **no join path at fact grain** between inventory and sourcing. The authoritative sourcing
relation lives in `supply_chain_analytics.dim_supplier_contract`, which **neither A nor B exposes at
all**. The only shared column is `PART_KEY`, on two facts of different grain.

| | Expected answer | Why |
| - | - | - |
| **A** | a supplier list from a `PART_KEY` join on `fact_supplier_quality` — fanned out across inspections, and **incomplete** | Inspection grain is not sourcing grain: it silently means "supplies this part **and** we have inspected it" → 45 of 60 contracted pairs |
| **B** | **declines** — "the metric views share no join path across domains" | Instruction says *never JOIN or UNION across domains*. Honest, correct, and useless |
| **C** | named suppliers per part, **plus** the reverse blast radius: every other warehouse and part that supplier touches | `kg_find_node('Pune')` → `partStockedAt` → `supplierSuppliesPart`, contract-derived (60 pairs, multi-sourcing kept — P0055 has three suppliers), then KPIs from `metrics_supplier_quality` |

**Score on:** does the answer exist at all, and is it *complete*? A's version looks plausible and
misses a quarter of the sourcing graph with no warning. B's refusal is the right answer to the wrong
question — a semantic layer can only certify measures over paths that already exist; it cannot
create a path. Only the graph can.

**Follow-up that only C can take:** *"which vehicle models does the Chennai plant actually build,
and on which lines?"* — `plantHasLine` + `lineProducesModel`, again no fact path.

---

## Scorecard to fill in live

| | Q1 weighted rollup | Q2 vocabulary & closed enum | Q3 relationships |
| - | - | - | - |
| **A** raw tables | | | |
| **B** + semantic layer | | | |
| **C** + ontology & KG | | | |

**The argument the three questions make together:**
Q1 — without the semantic layer the numbers are wrong. Q2 — with only the semantic layer the
numbers are *reliably* wrong wherever a business word was never defined. Q3 — the semantic layer
governs measures over existing joins; the ontology and graph are what let the agent answer a
question about how the business is *connected*.

## Before you run it

```sql
-- 1. Pune still has CRITICAL parts and no HIGH ones (Q2 depends entirely on this)
SELECT `Warehouse Name`, `Stockout Risk`, MEASURE(`Snapshot Row Count`)
FROM   gold_dev_analytics.supply_chain_analytics.metrics_inventory_snapshot
WHERE  `Is Current Snapshot` = true AND `Warehouse Name` ILIKE '%Pune%'
GROUP BY 1, 2 ORDER BY 2;
-- expect: CRITICAL 3, MEDIUM/LOW some, HIGH absent
-- if Pune loses that shape, swap in Ahmedabad RDC (1 HIGH, 4 CRITICAL) — weaker, B returns 1 row not 0

-- 2. the Q1 ranking flip is still there: AVG(PPM_LEVEL) must disagree with the weighted rollup
SELECT s.SUPPLIER_NAME,
       AVG(f.PPM_LEVEL)                                              AS avg_ppm_wrong,
       SUM(f.DEFECT_QTY) / NULLIF(SUM(f.INSPECTED_QTY), 0) * 1000000 AS weighted_ppm_right,
       SUM(f.COST_OF_POOR_QUALITY)                                   AS copq
FROM   gold_dev_analytics.supply_chain_analytics.fact_supplier_quality f
JOIN   gold_dev_analytics.dim.dim_supplier s ON s.SUPPLIER_KEY = f.SUPPLIER_KEY
GROUP  BY 1
ORDER  BY avg_ppm_wrong DESC;
-- expect: the top of avg_ppm_wrong is NOT the top of weighted_ppm_right or of copq.
-- if both orderings agree, pick the pair where they disagree most and use those two suppliers.

-- 3. the graph still reaches the suppliers (Q3)
SELECT DISTINCT s.node_name AS supplier, p.node_name AS part
FROM      gold_dev_analytics.ontology.kg_find_node('Pune') w,
  LATERAL gold_dev_analytics.ontology.kg_neighbors(w.node_type, w.node_key, 'partStockedAt') p,
  LATERAL gold_dev_analytics.ontology.kg_neighbors('Part', p.node_key, 'supplierSuppliesPart') s
WHERE p.node_name IN ('Blower Motor','Clutch Plate','Grommet');
```

Ask each question in a **fresh session per space** — a follow-up in the same thread inherits context
from the previous answer and contaminates the comparison.

*Numbers verified against `gold_dev_analytics` on 2026-09-09; see
[`the_one_question.md`](the_one_question.md) for the single-question version of the same argument.*
