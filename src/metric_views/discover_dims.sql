-- One-shot discovery of gold_dev fact + dim identifiers for metric-view joins.
-- Not part of the apply_metric_views job.
--
-- Run via SQL warehouse (example API body in comments below), then update column_map.md.

SHOW TABLES IN gold_dev.dim;

SELECT table_schema, table_name, column_name, data_type, ordinal_position
FROM gold_dev.information_schema.columns
WHERE (table_schema = 'dim' AND table_name IN (
  'dim_dealer','dim_vehicle_model','dim_date','dim_campaign','dim_channel',
  'dim_customer_segment','dim_plant','dim_production_line','dim_part','dim_warehouse','dim_supplier'
))
OR (table_schema = 'revenue_analytics' AND table_name = 'fact_sales_order')
OR (table_schema = 'marketing_analytics' AND table_name = 'fact_campaign_performance')
OR (table_schema = 'manufacturing_analytics' AND table_name = 'fact_production_execution')
OR (table_schema = 'supply_chain_analytics' AND table_name IN ('fact_inventory_snapshot','fact_supplier_quality'))
ORDER BY table_schema, table_name, ordinal_position;

-- Example request JSON for Databricks CLI:
-- {
--   "warehouse_id": "<warehouse_id>",
--   "statement": "<paste one statement>",
--   "wait_timeout": "50s"
-- }
-- databricks api post /api/2.0/sql/statements --profile gold --json @path/to/request.json
