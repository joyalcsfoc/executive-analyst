-- Re-derives each documented "KPI trap" formula independently from the fact tables
-- and diffs it against the certified MEASURE() on the metric view. Mirrors the traps
-- documented in src/ontology/benchmark_questions.md — see src/tests/README.md for the
-- cross-reference. A non-empty result means a measure formula regressed.
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev').
-- Tolerances: 0.0001 for ratio-scale measures (ROAS, CPL), 0.01 for money-scale sums
-- (revenue, bookings, discount) and PPM, to absorb floating-point rounding without
-- masking a real formula regression.

-- --- Diagnostic (0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT check_name, detail FROM (

  -- weighted ROAS must never be AVG(ROAS)
  SELECT 'weighted_roas_mismatch' AS check_name,
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(weighted_roas)=', CAST(view_val AS STRING)) AS detail
  FROM (
    SELECT
      (SELECT SUM(ROAS * ACTUAL_SPEND) / NULLIF(SUM(ACTUAL_SPEND), 0)
       FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance) AS fact_val,
      (SELECT MEASURE(weighted_roas) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.0001

  UNION ALL

  -- cost per lead must never be AVG(COST_PER_LEAD)
  SELECT 'cost_per_lead_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(cost_per_lead)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT SUM(ACTUAL_SPEND) / NULLIF(SUM(LEADS), 0)
       FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance) AS fact_val,
      (SELECT MEASURE(cost_per_lead) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.0001

  UNION ALL

  -- PPM is a ratio of sums, never SUM(PPM_LEVEL)
  SELECT 'ppm_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(ppm)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT SUM(DEFECT_QTY) / NULLIF(SUM(INSPECTED_QTY), 0) * 1000000
       FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality) AS fact_val,
      (SELECT MEASURE(ppm) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

  UNION ALL

  -- discount_percent is a 0-100 percent; never formatted or derived as currency
  SELECT 'discount_percent_out_of_range', CAST(view_val AS STRING)
  FROM (SELECT MEASURE(discount_percent) AS view_val FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order)
  WHERE view_val IS NOT NULL AND (view_val < 0 OR view_val > 100)

  UNION ALL

  SELECT 'discount_percent_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(discount_percent)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT 100 * SUM(DISCOUNT_AMOUNT) / NULLIF(SUM(ORDER_AMOUNT), 0)
       FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
      (SELECT MEASURE(discount_percent) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

  UNION ALL

  -- revenue must never be conflated with bookings: check each formula independently
  -- (not revenue <> bookings directly, since that inequality is data-dependent and
  -- could coincidentally hold even with a copy-paste aliasing bug)
  SELECT 'total_revenue_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(total_revenue)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT SUM(ORDER_AMOUNT) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
      (SELECT MEASURE(total_revenue) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

  UNION ALL

  SELECT 'total_bookings_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(total_bookings)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT SUM(BOOKING_AMOUNT) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
      (SELECT MEASURE(total_bookings) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

  UNION ALL

  -- delivered_order_revenue formula, and it must never exceed total_revenue
  SELECT 'delivered_order_revenue_mismatch',
    concat('fact=', CAST(fact_val AS STRING), ' view.MEASURE(delivered_order_revenue)=', CAST(view_val AS STRING))
  FROM (
    SELECT
      (SELECT SUM(ORDER_AMOUNT) FILTER (WHERE STATUS = 'DELIVERED')
       FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
      (SELECT MEASURE(delivered_order_revenue) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
  )
  WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

  UNION ALL

  SELECT 'delivered_order_revenue_exceeds_total_revenue',
    concat('delivered=', CAST(delivered AS STRING), ' total=', CAST(total AS STRING))
  FROM (
    SELECT MEASURE(delivered_order_revenue) AS delivered, MEASURE(total_revenue) AS total
    FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order
  )
  WHERE delivered > total + 0.01

  UNION ALL

  -- OEE / availability / performance / quality must be a 0-100 scale, not 0-1
  SELECT 'oee_component_out_of_range',
    concat('min_oee=', CAST(min_oee AS STRING), ' max_oee=', CAST(max_oee AS STRING),
           ' min_avail=', CAST(min_avail AS STRING), ' max_avail=', CAST(max_avail AS STRING),
           ' min_perf=', CAST(min_perf AS STRING), ' max_perf=', CAST(max_perf AS STRING),
           ' min_qual=', CAST(min_qual AS STRING), ' max_qual=', CAST(max_qual AS STRING))
  FROM (
    SELECT
      MIN(OEE_PCT) AS min_oee, MAX(OEE_PCT) AS max_oee,
      MIN(AVAILABILITY_PCT) AS min_avail, MAX(AVAILABILITY_PCT) AS max_avail,
      MIN(PERFORMANCE_PCT) AS min_perf, MAX(PERFORMANCE_PCT) AS max_perf,
      MIN(QUALITY_PCT) AS min_qual, MAX(QUALITY_PCT) AS max_qual
    FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution
  )
  WHERE min_oee < 0 OR max_oee > 100 OR min_avail < 0 OR max_avail > 100
     OR min_perf < 0 OR max_perf > 100 OR min_qual < 0 OR max_qual > 100

  UNION ALL

  -- oee_below_70 flag recomputed: aggregate flag-count parity stands in for a
  -- row-for-row check, since assert_view_row_counts.sql already proves the view
  -- has exactly 1 row per fact row
  SELECT 'oee_below_70_flag_mismatch',
    concat('fact_true_count=', CAST(fact_true_count AS STRING), ' view_true_count=', CAST(view_true_count AS STRING))
  FROM (
    SELECT
      (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution WHERE OEE_PCT < 70) AS fact_true_count,
      (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution WHERE oee_below_70 = true) AS view_true_count
  )
  WHERE fact_true_count <> view_true_count

)";

-- --- Gate ---

EXECUTE IMMEDIATE
"WITH violations AS (
  SELECT check_name FROM (

    SELECT 'weighted_roas_mismatch' AS check_name
    FROM (
      SELECT
        (SELECT SUM(ROAS * ACTUAL_SPEND) / NULLIF(SUM(ACTUAL_SPEND), 0)
         FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance) AS fact_val,
        (SELECT MEASURE(weighted_roas) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.0001

    UNION ALL

    SELECT 'cost_per_lead_mismatch'
    FROM (
      SELECT
        (SELECT SUM(ACTUAL_SPEND) / NULLIF(SUM(LEADS), 0)
         FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance) AS fact_val,
        (SELECT MEASURE(cost_per_lead) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.0001

    UNION ALL

    SELECT 'ppm_mismatch'
    FROM (
      SELECT
        (SELECT SUM(DEFECT_QTY) / NULLIF(SUM(INSPECTED_QTY), 0) * 1000000
         FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality) AS fact_val,
        (SELECT MEASURE(ppm) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

    UNION ALL

    SELECT 'discount_percent_out_of_range'
    FROM (SELECT MEASURE(discount_percent) AS view_val FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order)
    WHERE view_val IS NOT NULL AND (view_val < 0 OR view_val > 100)

    UNION ALL

    SELECT 'discount_percent_mismatch'
    FROM (
      SELECT
        (SELECT 100 * SUM(DISCOUNT_AMOUNT) / NULLIF(SUM(ORDER_AMOUNT), 0)
         FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
        (SELECT MEASURE(discount_percent) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

    UNION ALL

    SELECT 'total_revenue_mismatch'
    FROM (
      SELECT
        (SELECT SUM(ORDER_AMOUNT) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
        (SELECT MEASURE(total_revenue) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

    UNION ALL

    SELECT 'total_bookings_mismatch'
    FROM (
      SELECT
        (SELECT SUM(BOOKING_AMOUNT) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
        (SELECT MEASURE(total_bookings) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

    UNION ALL

    SELECT 'delivered_order_revenue_mismatch'
    FROM (
      SELECT
        (SELECT SUM(ORDER_AMOUNT) FILTER (WHERE STATUS = 'DELIVERED')
         FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_val,
        (SELECT MEASURE(delivered_order_revenue) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_val
    )
    WHERE ABS(COALESCE(fact_val, 0) - COALESCE(view_val, 0)) > 0.01

    UNION ALL

    SELECT 'delivered_order_revenue_exceeds_total_revenue'
    FROM (
      SELECT MEASURE(delivered_order_revenue) AS delivered, MEASURE(total_revenue) AS total
      FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order
    )
    WHERE delivered > total + 0.01

    UNION ALL

    SELECT 'oee_component_out_of_range'
    FROM (
      SELECT
        MIN(OEE_PCT) AS min_oee, MAX(OEE_PCT) AS max_oee,
        MIN(AVAILABILITY_PCT) AS min_avail, MAX(AVAILABILITY_PCT) AS max_avail,
        MIN(PERFORMANCE_PCT) AS min_perf, MAX(PERFORMANCE_PCT) AS max_perf,
        MIN(QUALITY_PCT) AS min_qual, MAX(QUALITY_PCT) AS max_qual
      FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution
    )
    WHERE min_oee < 0 OR max_oee > 100 OR min_avail < 0 OR max_avail > 100
       OR min_perf < 0 OR max_perf > 100 OR min_qual < 0 OR max_qual > 100

    UNION ALL

    SELECT 'oee_below_70_flag_mismatch'
    FROM (
      SELECT
        (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution WHERE OEE_PCT < 70) AS fact_true_count,
        (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution WHERE oee_below_70 = true) AS view_true_count
    )
    WHERE fact_true_count <> view_true_count

  )
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: all KPI trap formulas match their certified MEASURE()'
  ELSE raise_error(concat('FAIL: KPI formula regression in: ', concat_ws(', ', collect_set(check_name))))
END AS result
FROM violations";
