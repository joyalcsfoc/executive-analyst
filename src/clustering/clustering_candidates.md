# Gold fact table clustering candidates

Confirmed via repo-wide search: **no clustering, partitioning, or `OPTIMIZE`
scheduling exists anywhere today** — this is greenfield. As fact tables grow, Genie
query latency will degrade because every certified measure/filter in the metric
views hits the same handful of columns with no physical layout support.

Gold fact/dim tables are created upstream, outside this bundle. `ALTER TABLE ...
CLUSTER BY` is schema-affecting DDL on tables likely owned by another team —
**do not run [`cluster_gold_facts.sql`](cluster_gold_facts.sql) without that team's
sign-off.** Run [`discover_clustering_candidates.sql`](discover_clustering_candidates.sql)
first (read-only, safe anytime) and fill in the columns below before asking for
sign-off.

## Proposed `CLUSTER BY` keys

Date key first in every list: every metric view joins `dim_date`, and every question
in [`../ontology/benchmark_questions.md`](../ontology/benchmark_questions.md) is
time-scoped ("last month", "this quarter", "this week"). Liquid Clustering caps keys
at 4 columns, so lower-frequency keys (e.g. `SEGMENT_KEY`) are deferred pending real
query-history evidence rather than included by default.

| Fact table | Hot join keys | Hot filter | Proposed `CLUSTER BY` | Priority | Row count | Key cardinality |
| --- | --- | --- | --- | --- | --- | --- |
| `supply_chain_analytics.fact_inventory_snapshot` | `PART_KEY`, `WAREHOUSE_KEY` | `SNAPSHOT_DATE_KEY = MAX(...)` (`is_current_snapshot`) — every "current stock" question hits one date out of a growing daily history | `(SNAPSHOT_DATE_KEY, WAREHOUSE_KEY, PART_KEY)` | **Highest** — unbounded daily growth, extreme filter selectivity | _fill in_ | _fill in_ |
| `revenue_analytics.fact_sales_order` | `DEALER_KEY`, `MODEL_KEY` | `ORDER_DATE_KEY` range, `STATUS = 'DELIVERED'` | `(ORDER_DATE_KEY, DEALER_KEY, MODEL_KEY)` | High | _fill in_ | _fill in_ |
| `manufacturing_analytics.fact_production_execution` | `PLANT_KEY`, `LINE_KEY`, `MODEL_KEY` | `EXECUTION_DATE_KEY` range, `OEE_PCT < 70` | `(EXECUTION_DATE_KEY, PLANT_KEY, LINE_KEY)` | High | _fill in_ | _fill in_ |
| `supply_chain_analytics.fact_supplier_quality` | `SUPPLIER_KEY`, `PART_KEY` | `INSPECTION_DATE_KEY` range | `(INSPECTION_DATE_KEY, SUPPLIER_KEY, PART_KEY)` | Medium | _fill in_ | _fill in_ |
| `marketing_analytics.fact_campaign_performance` | `CAMPAIGN_KEY`, `CHANNEL_KEY`, `SEGMENT_KEY` | `START_DATE_KEY` range | `(START_DATE_KEY, CHANNEL_KEY, CAMPAIGN_KEY)` | Medium | _fill in_ | _fill in_ |

## Sign-off checklist before running `cluster_gold_facts.sql`

- [ ] `discover_clustering_candidates.sql` run against `gold_dev`; row counts and
      key cardinality above filled in.
- [ ] Gold-table-owning team has reviewed the proposed keys and approved the change.
- [ ] `ALTER TABLE ... CLUSTER BY` run against `gold_dev` first.
- [ ] `OPTIMIZE ... FULL` run against `gold_dev` to recluster data already on disk
      (metadata-only `ALTER TABLE` does not reorganize existing files).
- [ ] Before/after query timings captured for a handful of representative
      `benchmark_questions.md` questions (`EXPLAIN` / query profile duration).
- [ ] Owning team approves and executes (or explicitly delegates execution of) the
      same change against `gold`.
