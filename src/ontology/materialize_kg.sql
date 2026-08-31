-- Phase 3 — Delta property graph (ABox): ontology.kg_nodes + ontology.kg_edges
-- Job params: {{catalog}} expands to a quoted string (e.g. 'gold_dev').
-- KPI aggregations match metrics_* YAML expressions (MEASURE() not used in CTAS).
-- Edge `rel` values align with src/ontology/graph.yml object properties.
-- TBox (classes / object properties) remains glossary.yml + graph.yml → exec_analyst.ttl.
-- Do not invent Campaign → Order edges (no gold bridge).
-- Requires existing schema {catalog}.ontology (created outside this job).

-- ---------------------------------------------------------------------------
-- kg_nodes: one row per dim entity + optional KPI properties
-- ---------------------------------------------------------------------------
EXECUTE IMMEDIATE
"CREATE OR REPLACE TABLE " || {{catalog}} || ".ontology.kg_nodes AS
WITH
plant_kpi AS (
  SELECT
    PLANT_KEY AS source_key,
    AVG(OEE_PCT) AS average_oee,
    SUM(DOWNTIME_MIN) AS total_downtime
  FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution
  GROUP BY PLANT_KEY
),
part_kpi AS (
  SELECT
    f.PART_KEY AS source_key,
    MAX(f.STOCKOUT_RISK) AS stockout_risk,
    AVG(f.DAYS_OF_SUPPLY) AS average_days_of_supply
  FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot f
  WHERE f.SNAPSHOT_DATE_KEY = (
    SELECT MAX(SNAPSHOT_DATE_KEY)
    FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot
  )
  GROUP BY f.PART_KEY
),
supplier_kpi AS (
  SELECT
    SUPPLIER_KEY AS source_key,
    SUM(DEFECT_QTY) / NULLIF(SUM(INSPECTED_QTY), 0) * 1000000 AS ppm,
    SUM(COST_OF_POOR_QUALITY) AS copq
  FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality
  GROUP BY SUPPLIER_KEY
),
dealer_kpi AS (
  SELECT
    DEALER_KEY AS source_key,
    SUM(ORDER_AMOUNT) AS total_revenue_ytd
  FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order
  GROUP BY DEALER_KEY
),
campaign_kpi AS (
  SELECT
    CAMPAIGN_KEY AS source_key,
    SUM(ROAS * ACTUAL_SPEND) / NULLIF(SUM(ACTUAL_SPEND), 0) AS weighted_roas
  FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance
  GROUP BY CAMPAIGN_KEY
),
nodes AS (
  SELECT
    concat('Plant:', CAST(d.PLANT_KEY AS STRING)) AS node_id,
    'Plant' AS node_type,
    CAST(d.PLANT_KEY AS BIGINT) AS source_key,
    d.PLANT_NAME AS label,
    'manufacturing' AS domain,
    k.average_oee,
    k.total_downtime,
    CAST(NULL AS STRING) AS stockout_risk,
    CAST(NULL AS DOUBLE) AS average_days_of_supply,
    CAST(NULL AS DOUBLE) AS ppm,
    CAST(NULL AS DOUBLE) AS copq,
    CAST(NULL AS DOUBLE) AS total_revenue_ytd,
    CAST(NULL AS DOUBLE) AS weighted_roas
  FROM " || {{catalog}} || ".dim.dim_plant d
  LEFT JOIN plant_kpi k ON d.PLANT_KEY = k.source_key

  UNION ALL
  SELECT
    concat('ProductionLine:', CAST(d.LINE_KEY AS STRING)),
    'ProductionLine',
    CAST(d.LINE_KEY AS BIGINT),
    d.LINE_NAME,
    'manufacturing',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_production_line d

  UNION ALL
  SELECT
    concat('Model:', CAST(d.MODEL_KEY AS STRING)),
    'Model',
    CAST(d.MODEL_KEY AS BIGINT),
    d.MODEL_NAME,
    'finance',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_vehicle_model d

  UNION ALL
  SELECT
    concat('Dealer:', CAST(d.DEALER_KEY AS STRING)),
    'Dealer',
    CAST(d.DEALER_KEY AS BIGINT),
    d.DEALER_NAME,
    'finance',
    NULL, NULL, NULL, NULL, NULL, NULL,
    k.total_revenue_ytd,
    NULL
  FROM " || {{catalog}} || ".dim.dim_dealer d
  LEFT JOIN dealer_kpi k ON d.DEALER_KEY = k.source_key

  UNION ALL
  SELECT
    concat('Part:', CAST(d.PART_KEY AS STRING)),
    'Part',
    CAST(d.PART_KEY AS BIGINT),
    d.PART_NAME,
    'supply_chain',
    NULL, NULL,
    k.stockout_risk,
    k.average_days_of_supply,
    NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_part d
  LEFT JOIN part_kpi k ON d.PART_KEY = k.source_key

  UNION ALL
  SELECT
    concat('Warehouse:', CAST(d.WAREHOUSE_KEY AS STRING)),
    'Warehouse',
    CAST(d.WAREHOUSE_KEY AS BIGINT),
    d.WAREHOUSE_NAME,
    'supply_chain',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_warehouse d

  UNION ALL
  SELECT
    concat('Supplier:', CAST(d.SUPPLIER_KEY AS STRING)),
    'Supplier',
    CAST(d.SUPPLIER_KEY AS BIGINT),
    d.SUPPLIER_NAME,
    'quality',
    NULL, NULL, NULL, NULL,
    k.ppm,
    k.copq,
    NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_supplier d
  LEFT JOIN supplier_kpi k ON d.SUPPLIER_KEY = k.source_key

  UNION ALL
  SELECT
    concat('Campaign:', CAST(d.CAMPAIGN_KEY AS STRING)),
    'Campaign',
    CAST(d.CAMPAIGN_KEY AS BIGINT),
    d.CAMPAIGN_NAME,
    'marketing',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    k.weighted_roas
  FROM " || {{catalog}} || ".dim.dim_campaign d
  LEFT JOIN campaign_kpi k ON d.CAMPAIGN_KEY = k.source_key

  UNION ALL
  SELECT
    concat('Channel:', CAST(d.CHANNEL_KEY AS STRING)),
    'Channel',
    CAST(d.CHANNEL_KEY AS BIGINT),
    d.CHANNEL_NAME,
    'marketing',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_channel d

  UNION ALL
  SELECT
    concat('Segment:', CAST(d.SEGMENT_KEY AS STRING)),
    'Segment',
    CAST(d.SEGMENT_KEY AS BIGINT),
    d.SEGMENT_NAME,
    'marketing',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM " || {{catalog}} || ".dim.dim_customer_segment d
)
SELECT
  node_id,
  node_type,
  source_key,
  label,
  domain,
  average_oee,
  total_downtime,
  stockout_risk,
  average_days_of_supply,
  ppm,
  copq,
  total_revenue_ytd,
  weighted_roas,
  current_timestamp() AS refreshed_at
FROM nodes";

-- ---------------------------------------------------------------------------
-- kg_edges: distinct key pairs from facts (rel matches graph.yml)
-- ---------------------------------------------------------------------------
EXECUTE IMMEDIATE
"CREATE OR REPLACE TABLE " || {{catalog}} || ".ontology.kg_edges AS
SELECT src_id, dst_id, rel, domain, current_timestamp() AS refreshed_at
FROM (
  SELECT DISTINCT
    concat('Plant:', CAST(PLANT_KEY AS STRING)) AS src_id,
    concat('ProductionLine:', CAST(LINE_KEY AS STRING)) AS dst_id,
    'hasLine' AS rel,
    'manufacturing' AS domain
  FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution
  WHERE PLANT_KEY IS NOT NULL AND LINE_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('ProductionLine:', CAST(LINE_KEY AS STRING)),
    concat('Model:', CAST(MODEL_KEY AS STRING)),
    'produces',
    'manufacturing'
  FROM " || {{catalog}} || ".manufacturing_analytics.fact_production_execution
  WHERE LINE_KEY IS NOT NULL AND MODEL_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('Model:', CAST(MODEL_KEY AS STRING)),
    concat('Dealer:', CAST(DEALER_KEY AS STRING)),
    'soldBy',
    'finance'
  FROM " || {{catalog}} || ".revenue_analytics.fact_sales_order
  WHERE MODEL_KEY IS NOT NULL AND DEALER_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('Part:', CAST(PART_KEY AS STRING)),
    concat('Warehouse:', CAST(WAREHOUSE_KEY AS STRING)),
    'stockedAt',
    'supply_chain'
  FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot
  WHERE SNAPSHOT_DATE_KEY = (
    SELECT MAX(SNAPSHOT_DATE_KEY)
    FROM " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot
  )
    AND PART_KEY IS NOT NULL
    AND WAREHOUSE_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('Supplier:', CAST(SUPPLIER_KEY AS STRING)),
    concat('Part:', CAST(PART_KEY AS STRING)),
    'supplies',
    'quality'
  FROM " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality
  WHERE SUPPLIER_KEY IS NOT NULL AND PART_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('Campaign:', CAST(CAMPAIGN_KEY AS STRING)),
    concat('Channel:', CAST(CHANNEL_KEY AS STRING)),
    'runsOnChannel',
    'marketing'
  FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance
  WHERE CAMPAIGN_KEY IS NOT NULL AND CHANNEL_KEY IS NOT NULL

  UNION ALL
  SELECT DISTINCT
    concat('Campaign:', CAST(CAMPAIGN_KEY AS STRING)),
    concat('Segment:', CAST(SEGMENT_KEY AS STRING)),
    'runsOnSegment',
    'marketing'
  FROM " || {{catalog}} || ".marketing_analytics.fact_campaign_performance
  WHERE CAMPAIGN_KEY IS NOT NULL AND SEGMENT_KEY IS NOT NULL
)";
