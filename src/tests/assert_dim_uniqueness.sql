-- Verify the `rely: { at_most_one_match: true }` assumption behind every dim join
-- in the five metrics_* views. If a dim key is ever duplicated, the metric-view
-- join silently fans out and every measure built on it becomes wrong with no signal.
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev').
-- Checked once per dim table (not once per view) since the uniqueness property
-- belongs to the dim, not to the view that joins it.

-- --- Diagnostic (run ad hoc in the SQL editor; lists every duplicated key, 0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT dim_table, key_column, key_value, dup_count FROM (
  SELECT 'dim_dealer' AS dim_table, 'DEALER_KEY' AS key_column, CAST(DEALER_KEY AS STRING) AS key_value, COUNT(*) AS dup_count
  FROM " || {{catalog}} || ".dim.dim_dealer GROUP BY DEALER_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_vehicle_model', 'MODEL_KEY', CAST(MODEL_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_vehicle_model GROUP BY MODEL_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_campaign', 'CAMPAIGN_KEY', CAST(CAMPAIGN_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_campaign GROUP BY CAMPAIGN_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_channel', 'CHANNEL_KEY', CAST(CHANNEL_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_channel GROUP BY CHANNEL_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_customer_segment', 'SEGMENT_KEY', CAST(SEGMENT_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_customer_segment GROUP BY SEGMENT_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_plant', 'PLANT_KEY', CAST(PLANT_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_plant GROUP BY PLANT_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_production_line', 'LINE_KEY', CAST(LINE_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_production_line GROUP BY LINE_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_part', 'PART_KEY', CAST(PART_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_part GROUP BY PART_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_warehouse', 'WAREHOUSE_KEY', CAST(WAREHOUSE_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_warehouse GROUP BY WAREHOUSE_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_supplier', 'SUPPLIER_KEY', CAST(SUPPLIER_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_supplier GROUP BY SUPPLIER_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_date', 'DATE_KEY', CAST(DATE_KEY AS STRING), COUNT(*)
  FROM " || {{catalog}} || ".dim.dim_date GROUP BY DATE_KEY HAVING COUNT(*) > 1
) ORDER BY dim_table, key_value";

-- --- Gate (run by the validate_metric_views job; fails the task on any violation) ---

EXECUTE IMMEDIATE
"WITH violations AS (
  SELECT 'dim_dealer' AS dim_table FROM " || {{catalog}} || ".dim.dim_dealer GROUP BY DEALER_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_vehicle_model' FROM " || {{catalog}} || ".dim.dim_vehicle_model GROUP BY MODEL_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_campaign' FROM " || {{catalog}} || ".dim.dim_campaign GROUP BY CAMPAIGN_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_channel' FROM " || {{catalog}} || ".dim.dim_channel GROUP BY CHANNEL_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_customer_segment' FROM " || {{catalog}} || ".dim.dim_customer_segment GROUP BY SEGMENT_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_plant' FROM " || {{catalog}} || ".dim.dim_plant GROUP BY PLANT_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_production_line' FROM " || {{catalog}} || ".dim.dim_production_line GROUP BY LINE_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_part' FROM " || {{catalog}} || ".dim.dim_part GROUP BY PART_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_warehouse' FROM " || {{catalog}} || ".dim.dim_warehouse GROUP BY WAREHOUSE_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_supplier' FROM " || {{catalog}} || ".dim.dim_supplier GROUP BY SUPPLIER_KEY HAVING COUNT(*) > 1
  UNION ALL
  SELECT 'dim_date' FROM " || {{catalog}} || ".dim.dim_date GROUP BY DATE_KEY HAVING COUNT(*) > 1
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: all 11 dim tables satisfy at_most_one_match'
  ELSE raise_error(concat('FAIL: at_most_one_match violated in: ', concat_ws(', ', collect_set(dim_table))))
END AS result
FROM violations";
