-- Inventory-snapshot-specific traps: a snapshot fact must never be summed across
-- dates, and the current-snapshot / stockout flags must match the enum they derive
-- from. Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev').

-- --- Diagnostic (0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT check_name, detail FROM (

  -- is_current_snapshot must select exactly one date: the latest SNAPSHOT_DATE_KEY
  SELECT 'is_current_snapshot_not_single_date' AS check_name,
    concat('distinct_dates=', CAST(distinct_dates AS STRING),
           ' current_max=', CAST(current_max AS STRING), ' fact_max=', CAST(fact_max AS STRING)) AS detail
  FROM (
    SELECT
      (SELECT COUNT(DISTINCT SNAPSHOT_DATE_KEY)
       FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot
       WHERE is_current_snapshot = true) AS distinct_dates,
      (SELECT MAX(SNAPSHOT_DATE_KEY)
       FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot
       WHERE is_current_snapshot = true) AS current_max,
      (SELECT MAX(SNAPSHOT_DATE_KEY)
       FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot) AS fact_max
  )
  WHERE distinct_dates <> 1 OR current_max <> fact_max

  UNION ALL

  -- high_stockout flag recomputed (aggregate parity; row count already 1:1 with fact
  -- per assert_view_row_counts.sql)
  SELECT 'high_stockout_flag_mismatch',
    concat('fact_true_count=', CAST(fact_true_count AS STRING), ' view_true_count=', CAST(view_true_count AS STRING))
  FROM (
    SELECT
      (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot WHERE STOCKOUT_RISK = 'HIGH') AS fact_true_count,
      (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot WHERE high_stockout = true) AS view_true_count
  )
  WHERE fact_true_count <> view_true_count

  UNION ALL

  -- restock_candidate flag recomputed (HIGH or MEDIUM)
  SELECT 'restock_candidate_flag_mismatch',
    concat('fact_true_count=', CAST(fact_true_count AS STRING), ' view_true_count=', CAST(view_true_count AS STRING))
  FROM (
    SELECT
      (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot WHERE STOCKOUT_RISK IN ('HIGH', 'MEDIUM')) AS fact_true_count,
      (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot WHERE restock_candidate = true) AS view_true_count
  )
  WHERE fact_true_count <> view_true_count

)";

-- --- Gate ---

EXECUTE IMMEDIATE
"WITH violations AS (
  SELECT check_name FROM (

    SELECT 'is_current_snapshot_not_single_date' AS check_name
    FROM (
      SELECT
        (SELECT COUNT(DISTINCT SNAPSHOT_DATE_KEY)
         FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot
         WHERE is_current_snapshot = true) AS distinct_dates,
        (SELECT MAX(SNAPSHOT_DATE_KEY)
         FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot
         WHERE is_current_snapshot = true) AS current_max,
        (SELECT MAX(SNAPSHOT_DATE_KEY)
         FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot) AS fact_max
    )
    WHERE distinct_dates <> 1 OR current_max <> fact_max

    UNION ALL

    SELECT 'high_stockout_flag_mismatch'
    FROM (
      SELECT
        (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot WHERE STOCKOUT_RISK = 'HIGH') AS fact_true_count,
        (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot WHERE high_stockout = true) AS view_true_count
    )
    WHERE fact_true_count <> view_true_count

    UNION ALL

    SELECT 'restock_candidate_flag_mismatch'
    FROM (
      SELECT
        (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot WHERE STOCKOUT_RISK IN ('HIGH', 'MEDIUM')) AS fact_true_count,
        (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot WHERE restock_candidate = true) AS view_true_count
    )
    WHERE fact_true_count <> view_true_count

  )
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: inventory snapshot grain and stockout flags are correct'
  ELSE raise_error(concat('FAIL: inventory snapshot check(s) failed: ', concat_ws(', ', collect_set(check_name))))
END AS result
FROM violations";
