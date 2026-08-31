-- DO NOT RUN WITHOUT GOLD-TABLE-OWNER SIGN-OFF.
--
-- Adds Liquid Clustering to the five gold fact tables backing the Executive
-- Analyst metric views. These tables are created and owned upstream, outside this
-- bundle — this is schema-affecting DDL on shared tables this repo does not own.
--
-- This file is NOT wired into any Databricks Job or deploy.sh action (same
-- precedent as metrics_*.sql's CREATE OR REPLACE VIEW, which is also run manually).
-- Run once against gold_dev first, capture before/after evidence in
-- clustering_candidates.md, and only then run against gold with the owning team's
-- explicit approval — see the sign-off checklist there.
--
-- Rationale for each key list: src/clustering/clustering_candidates.md.
-- Replace catalog gold_dev with gold for prod, same as kg_queries.sql.

-- ---------------------------------------------------------------------------
-- Highest priority: unbounded daily growth, single-date filter on every
-- "current stock" / stockout question.
-- ---------------------------------------------------------------------------

ALTER TABLE gold_dev.supply_chain_analytics.fact_inventory_snapshot
CLUSTER BY (SNAPSHOT_DATE_KEY, WAREHOUSE_KEY, PART_KEY);

-- ---------------------------------------------------------------------------
-- High priority
-- ---------------------------------------------------------------------------

ALTER TABLE gold_dev.revenue_analytics.fact_sales_order
CLUSTER BY (ORDER_DATE_KEY, DEALER_KEY, MODEL_KEY);

ALTER TABLE gold_dev.manufacturing_analytics.fact_production_execution
CLUSTER BY (EXECUTION_DATE_KEY, PLANT_KEY, LINE_KEY);

-- ---------------------------------------------------------------------------
-- Medium priority
-- ---------------------------------------------------------------------------

ALTER TABLE gold_dev.supply_chain_analytics.fact_supplier_quality
CLUSTER BY (INSPECTION_DATE_KEY, SUPPLIER_KEY, PART_KEY);

ALTER TABLE gold_dev.marketing_analytics.fact_campaign_performance
CLUSTER BY (START_DATE_KEY, CHANNEL_KEY, CAMPAIGN_KEY);

-- ---------------------------------------------------------------------------
-- ALTER TABLE ... CLUSTER BY is metadata-only: it declares the clustering key
-- but does not reorganize data already on disk. Run OPTIMIZE FULL once per table
-- to recluster existing history. Left commented by default — this is a compute
-- cost / compaction operation on someone else's table, and deserves its own
-- deliberate opt-in separate from the ALTER TABLE above.
-- ---------------------------------------------------------------------------

-- OPTIMIZE gold_dev.supply_chain_analytics.fact_inventory_snapshot FULL;
-- OPTIMIZE gold_dev.revenue_analytics.fact_sales_order FULL;
-- OPTIMIZE gold_dev.manufacturing_analytics.fact_production_execution FULL;
-- OPTIMIZE gold_dev.supply_chain_analytics.fact_supplier_quality FULL;
-- OPTIMIZE gold_dev.marketing_analytics.fact_campaign_performance FULL;
