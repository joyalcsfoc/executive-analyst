# Glossary → asset wiring checklist

**System of record for wiring:** Unity Catalog tags (`glossary_terms`, `glossary_source`) applied by [`../metric_views/tag_metric_views.sql`](../metric_views/tag_metric_views.sql), generated from [`exec_analyst.ttl`](exec_analyst.ttl) by [`generate.py`](generate.py).

**Catalog Explorer Glossary / Pages Assign — deferred.** Databricks Glossary is not GA in this workspace, and there is no public REST/SDK upsert. Do **not** invent a parallel glossary store. Check a box below only when Glossary Pages exist **and** you have assigned the term in the UI (optional mirror). Tags alone satisfy Step 3 / Step 5.

Ambiguous terms `cost` and `efficiency` have no `links_to` — leave for Genie policy (Step 4).

## Measures

- [ ] **revenue** → `revenue_analytics.metrics_sales_order` measure `total_revenue`
- [ ] **bookings** → `revenue_analytics.metrics_sales_order` measure `total_bookings`
- [ ] **discount** → `revenue_analytics.metrics_sales_order` measure `total_discount`
- [ ] **delivered_order** → `revenue_analytics.metrics_sales_order` measure `delivered_order_revenue`
- [ ] **delivered_order** → `revenue_analytics.metrics_sales_order` field `order_status`
- [ ] **roas** → `marketing_analytics.metrics_campaign_performance` measure `weighted_roas`
- [ ] **cpl** → `marketing_analytics.metrics_campaign_performance` measure `cost_per_lead`
- [ ] **conversion_marketing** → `marketing_analytics.metrics_campaign_performance` measure `total_conversions`
- [ ] **oee** → `manufacturing_analytics.metrics_production_execution` measure `average_oee`
- [ ] **oee** → `manufacturing_analytics.metrics_production_execution` field `oee_below_70`
- [ ] **downtime** → `manufacturing_analytics.metrics_production_execution` measure `total_downtime`
- [ ] **stockout_risk** → `supply_chain_analytics.metrics_inventory_snapshot` field `stockout_risk`
- [ ] **stockout_risk** → `supply_chain_analytics.metrics_inventory_snapshot` field `high_stockout`
- [ ] **days_of_supply** → `supply_chain_analytics.metrics_inventory_snapshot` measure `average_days_of_supply`
- [ ] **inventory_turnover** → `supply_chain_analytics.metrics_inventory_snapshot` measure `average_turnover`
- [ ] **ppm** → `supply_chain_analytics.metrics_supplier_quality` measure `ppm`
- [ ] **copq** → `supply_chain_analytics.metrics_supplier_quality` measure `copq`

## Entities

- [ ] **plant** → `manufacturing_analytics.metrics_production_execution` field `plant_name`
- [ ] **plant** → table `dim.dim_plant`
- [ ] **production_line** → `manufacturing_analytics.metrics_production_execution` field `line_name`
- [ ] **production_line** → table `dim.dim_production_line`
- [ ] **part** → `supply_chain_analytics.metrics_inventory_snapshot` field `part_name`
- [ ] **part** → `supply_chain_analytics.metrics_supplier_quality` field `part_name`
- [ ] **part** → table `dim.dim_part`
- [ ] **warehouse** → `supply_chain_analytics.metrics_inventory_snapshot` field `warehouse_name`
- [ ] **warehouse** → table `dim.dim_warehouse`
- [ ] **supplier** → `supply_chain_analytics.metrics_supplier_quality` field `supplier_name`
- [ ] **supplier** → table `dim.dim_supplier`
- [ ] **dealer** → `revenue_analytics.metrics_sales_order` field `dealer_name`
- [ ] **dealer** → table `dim.dim_dealer`
- [ ] **model** → `revenue_analytics.metrics_sales_order` field `model_name`
- [ ] **model** → `manufacturing_analytics.metrics_production_execution` field `model_name`
- [ ] **model** → table `dim.dim_vehicle_model`
- [ ] **campaign** → `marketing_analytics.metrics_campaign_performance` field `campaign_name`
- [ ] **campaign** → table `dim.dim_campaign`
- [ ] **channel** → `marketing_analytics.metrics_campaign_performance` field `channel_name`
- [ ] **channel** → table `dim.dim_channel`
- [ ] **segment** → `marketing_analytics.metrics_campaign_performance` field `segment_name`
- [ ] **segment** → table `dim.dim_customer_segment`

## Verify tags (SQL)

```sql
SELECT schema_name, table_name, tag_name, tag_value
FROM gold_dev.information_schema.table_tags
WHERE tag_name IN ('glossary_terms', 'glossary_source', 'domain', 'grain', 'kpi')
  AND (
    table_name LIKE 'metrics_%'
    OR table_name IN (
      'dim_plant','dim_production_line','dim_part','dim_warehouse','dim_supplier',
      'dim_dealer','dim_vehicle_model','dim_campaign','dim_channel','dim_customer_segment'
    )
  )
ORDER BY schema_name, table_name, tag_name;
```

## When Glossary Pages become available

1. Create terms from `exec_analyst.ttl` (KPI and entity classes) in Catalog Explorer (or use the REST upsert job when Databricks ships a public Glossary API).
2. Assign each term to the assets listed above.
3. Check the matching boxes in this file.
4. Keep Git as source of truth — edit YAML first, then mirror to the UI.
