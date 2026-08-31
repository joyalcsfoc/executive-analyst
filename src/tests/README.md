# Semantic-layer SQL test suite

Automated, repeatable proof that the KPI "traps" documented in
[`src/ontology/benchmark_questions.md`](../ontology/benchmark_questions.md) actually
hold in the SQL, instead of relying only on a human asking Genie the right questions.

**Division of labor:** `benchmark_questions.md` is a Genie prompt/UX eval — it checks
whether the agent *routes* a natural-language question to the right measure. This
folder is a SQL-correctness eval — it checks whether the measure *formula itself* is
still right, independent of Genie. Both are needed; they test different failure modes
and should not be merged.

## Pattern

Each file contains two statements:

1. **Diagnostic** — a plain `SELECT` you can paste into a SQL editor. Returns 0 rows
   on pass; one row per violation on failure, with enough detail to act on directly.
2. **Gate** — the same predicate wrapped so a non-empty result calls `raise_error(...)`.
   This makes the *statement* throw, which fails the Databricks SQL *task*, which fails
   the *job run* — the mechanism `validate_metric_views`
   ([`../../resources/validate_metric_views_job.yml`](../../resources/validate_metric_views_job.yml))
   uses to go red in the Jobs UI without any external test runner.

Both statements are read-only `SELECT`s — safe to run anytime, including against prod.

## Files

| File | Checks | Cross-reference in `benchmark_questions.md` |
| --- | --- | --- |
| [`assert_dim_uniqueness.sql`](assert_dim_uniqueness.sql) | `rely: { at_most_one_match: true }` holds for all 11 dim tables backing the 5 views' joins | Underpins every question — a violation here silently breaks every KPI |
| [`assert_view_row_counts.sql`](assert_view_row_counts.sql) | Each `metrics_*` view has the same row count as its source fact (fan-out canary) | Same as above |
| [`assert_kpi_formulas.sql`](assert_kpi_formulas.sql) | weighted ROAS ≠ `AVG(ROAS)`; CPL ≠ `AVG(COST_PER_LEAD)`; PPM is ratio-of-sums not `SUM(PPM_LEVEL)`; `discount_percent` is 0–100 and never currency; `total_revenue` ≠ `total_bookings` formulas; `delivered_order_revenue` ≤ `total_revenue`; OEE/availability/performance/quality are 0–100 scale; `oee_below_70` flag | PRD #2, #5, #6, #7; C4, C6, C7, C17, C21, C25 (ROAS/CPL/PPM/discount/revenue-vs-bookings); PRD #3; C18, C26 (OEE) |
| [`assert_snapshot_grain.sql`](assert_snapshot_grain.sql) | `is_current_snapshot` spans exactly one date, equal to `MAX(SNAPSHOT_DATE_KEY)`; `high_stockout` / `restock_candidate` flags match `STOCKOUT_RISK` | PRD #4; #11, #14, C23, C24, C27 (snapshot-summing trap) |
| [`assert_kg_integrity.sql`](assert_kg_integrity.sql) | `ontology.kg_edges` has no orphan endpoints; `ontology.kg_nodes.node_id` is unique; every edge `rel` is declared in [`../ontology/graph.yml`](../ontology/graph.yml); every edge's endpoint node types match that `rel`'s domain/range | n/a — graph structure, not a Genie KPI trap |

If you add or change a trap in `benchmark_questions.md`, add or update the matching
assertion here — and vice versa. They are meant to stay in sync, not drift apart.

## Running

```bash
./deploy.sh test-metrics --target dev
```

Or run an individual file's statements directly in a SQL editor against the warehouse
in `databricks.yml` for ad hoc debugging.
