-- Read-only grants for the wrapper app's service principal (guardrail Phase 1).
-- Job params: {{catalog}} and {{agent_sp}} expand to quoted strings
--   (e.g. 'gold_dev_analytics', 'd57c77a6-40e2-48a3-b2c8-d322c9e99471').
--
-- SELECT and USE only. Deliberately NOT catalog-wide ALL PRIVILEGES: the agent's
-- reachable surface is meant to be exactly the five metric views, five facts,
-- the dims they join, and the ontology KG functions -- so that "what can it see"
-- is answered by this file rather than by whatever ends up in the catalog later.
--
-- Paired with src/tests/assert_readonly.sql, which proves the write path fails.

-- --- Catalog / schema traversal (USE does not grant data access) ---

EXECUTE IMMEDIATE
"GRANT USE CATALOG ON CATALOG " || {{catalog}} || " TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".revenue_analytics TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".marketing_analytics TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".manufacturing_analytics TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".supply_chain_analytics TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".dim TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT USE SCHEMA ON SCHEMA " || {{catalog}} || ".ontology TO `" || {{agent_sp}} || "`";

-- --- Metric views (the certified KPI surface) ---

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".revenue_analytics.metrics_sales_order TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality TO `" || {{agent_sp}} || "`";

-- --- Fact tables (row-level drill only; KPIs must come from the views above) ---

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".revenue_analytics.fact_sales_order TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".marketing_analytics.fact_campaign_performance TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".manufacturing_analytics.fact_production_execution TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".supply_chain_analytics.fact_inventory_snapshot TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".supply_chain_analytics.fact_supplier_quality TO `" || {{agent_sp}} || "`";

-- --- Dim tables (same list as src/metric_views/grant_metric_views.sql) ---

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_plant TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_production_line TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_part TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_warehouse TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_supplier TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_dealer TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_vehicle_model TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_campaign TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_channel TO `" || {{agent_sp}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_customer_segment TO `" || {{agent_sp}} || "`";
