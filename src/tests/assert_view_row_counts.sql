-- Fan-out canary: if a dim join ever violates at_most_one_match (see
-- assert_dim_uniqueness.sql), rows multiply and every SUM/AVG/COUNT measure on the
-- affected metrics_* view becomes silently wrong. Row-count parity with the source
-- fact table is the cheapest independent signal that no join fanned out.
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev').

-- --- Diagnostic (0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT view_name, fact_name, view_count, fact_count, view_count - fact_count AS row_diff FROM (
  SELECT 'metrics_sales_order' AS view_name, 'fact_sales_order' AS fact_name,
    (SELECT COUNT(*) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_count,
    (SELECT COUNT(*) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_count
  UNION ALL
  SELECT 'metrics_campaign_performance', 'fact_campaign_performance',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance)
  UNION ALL
  SELECT 'metrics_production_execution', 'fact_production_execution',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution)
  UNION ALL
  SELECT 'metrics_inventory_snapshot', 'fact_inventory_snapshot',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot)
  UNION ALL
  SELECT 'metrics_supplier_quality', 'fact_supplier_quality',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality)
) WHERE view_count <> fact_count";

-- --- Gate ---

EXECUTE IMMEDIATE
"WITH counts AS (
  SELECT 'metrics_sales_order' AS view_name,
    (SELECT COUNT(*) FROM " || {{catalog}} || ".revenue_analytics.metrics_sales_order) AS view_count,
    (SELECT COUNT(*) FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order) AS fact_count
  UNION ALL
  SELECT 'metrics_campaign_performance',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance)
  UNION ALL
  SELECT 'metrics_production_execution',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution)
  UNION ALL
  SELECT 'metrics_inventory_snapshot',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot)
  UNION ALL
  SELECT 'metrics_supplier_quality',
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality),
    (SELECT COUNT(*) FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality)
),
violations AS (
  SELECT view_name FROM counts WHERE view_count <> fact_count
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: all 5 metrics_* views match their source fact row count'
  ELSE raise_error(concat('FAIL: row-count mismatch (possible join fan-out) in: ', concat_ws(', ', collect_set(view_name))))
END AS result
FROM violations";
