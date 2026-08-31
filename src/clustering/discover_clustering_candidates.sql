-- One-shot discovery of gold fact table size and candidate clustering-key
-- cardinality, to decide whether/how to add Liquid Clustering (CLUSTER BY).
-- Read-only. Not part of any job or deploy.sh action — same precedent as
-- src/metric_views/discover_dims.sql. Run against a target catalog, then fill the
-- results into clustering_candidates.md.
--
-- Run via SQL warehouse, e.g.:
--   databricks api post /api/2.0/sql/statements --profile gold --json @path/to/request.json
-- with body: {"warehouse_id": "<warehouse_id>", "statement": "<paste one statement>", "wait_timeout": "50s"}

-- ---------------------------------------------------------------------------
-- 1. Baseline size / file count per fact table (evidence for "is it worth it yet")
-- ---------------------------------------------------------------------------

DESCRIBE DETAIL gold_dev.revenue_analytics.fact_sales_order;
DESCRIBE DETAIL gold_dev.marketing_analytics.fact_campaign_performance;
DESCRIBE DETAIL gold_dev.manufacturing_analytics.fact_production_execution;
DESCRIBE DETAIL gold_dev.supply_chain_analytics.fact_inventory_snapshot;
DESCRIBE DETAIL gold_dev.supply_chain_analytics.fact_supplier_quality;

-- ---------------------------------------------------------------------------
-- 2. Cardinality of each candidate clustering key (Liquid Clustering wants
--    medium/high-cardinality columns, not near-constants)
-- ---------------------------------------------------------------------------

SELECT
  APPROX_COUNT_DISTINCT(ORDER_DATE_KEY) AS distinct_order_date_key,
  APPROX_COUNT_DISTINCT(DEALER_KEY) AS distinct_dealer_key,
  APPROX_COUNT_DISTINCT(MODEL_KEY) AS distinct_model_key,
  COUNT(*) AS row_count
FROM gold_dev.revenue_analytics.fact_sales_order;

SELECT
  APPROX_COUNT_DISTINCT(START_DATE_KEY) AS distinct_start_date_key,
  APPROX_COUNT_DISTINCT(CHANNEL_KEY) AS distinct_channel_key,
  APPROX_COUNT_DISTINCT(CAMPAIGN_KEY) AS distinct_campaign_key,
  APPROX_COUNT_DISTINCT(SEGMENT_KEY) AS distinct_segment_key,
  COUNT(*) AS row_count
FROM gold_dev.marketing_analytics.fact_campaign_performance;

SELECT
  APPROX_COUNT_DISTINCT(EXECUTION_DATE_KEY) AS distinct_execution_date_key,
  APPROX_COUNT_DISTINCT(PLANT_KEY) AS distinct_plant_key,
  APPROX_COUNT_DISTINCT(LINE_KEY) AS distinct_line_key,
  COUNT(*) AS row_count
FROM gold_dev.manufacturing_analytics.fact_production_execution;

SELECT
  APPROX_COUNT_DISTINCT(SNAPSHOT_DATE_KEY) AS distinct_snapshot_date_key,
  APPROX_COUNT_DISTINCT(WAREHOUSE_KEY) AS distinct_warehouse_key,
  APPROX_COUNT_DISTINCT(PART_KEY) AS distinct_part_key,
  COUNT(*) AS row_count
FROM gold_dev.supply_chain_analytics.fact_inventory_snapshot;

SELECT
  APPROX_COUNT_DISTINCT(INSPECTION_DATE_KEY) AS distinct_inspection_date_key,
  APPROX_COUNT_DISTINCT(SUPPLIER_KEY) AS distinct_supplier_key,
  APPROX_COUNT_DISTINCT(PART_KEY) AS distinct_part_key,
  COUNT(*) AS row_count
FROM gold_dev.supply_chain_analytics.fact_supplier_quality;

-- ---------------------------------------------------------------------------
-- 3. Best-effort: confirm which columns are actually filtered/joined on most,
--    if the system.query.history UC system schema is enabled in this workspace.
--    (Enablement can't be confirmed from this repo — check Catalog Explorer >
--    system catalog > query > history first.)
-- ---------------------------------------------------------------------------

-- SELECT statement_text, COUNT(*) AS exec_count
-- FROM system.query.history
-- WHERE statement_text ILIKE '%fact_sales_order%'
--    OR statement_text ILIKE '%fact_campaign_performance%'
--    OR statement_text ILIKE '%fact_production_execution%'
--    OR statement_text ILIKE '%fact_inventory_snapshot%'
--    OR statement_text ILIKE '%fact_supplier_quality%'
--    OR statement_text ILIKE '%metrics_sales_order%'
--    OR statement_text ILIKE '%metrics_campaign_performance%'
--    OR statement_text ILIKE '%metrics_production_execution%'
--    OR statement_text ILIKE '%metrics_inventory_snapshot%'
--    OR statement_text ILIKE '%metrics_supplier_quality%'
-- GROUP BY statement_text
-- ORDER BY exec_count DESC
-- LIMIT 100;
