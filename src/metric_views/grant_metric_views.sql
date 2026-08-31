-- Grant SELECT on Executive Analyst metric views + linked dims (Step 6 ACL prep).
-- Job params: {{catalog}} and {{grant_group}} expand to quoted strings (e.g. 'gold_dev', 'users').
-- Principal matches bundle var genie_space_permission_group so Genie users see the same UC assets.
-- Does not revoke fact SELECT; Genie instructions still prefer metrics_* for KPIs.
-- Warehouse identity still needs SELECT on facts/dims and CREATE VIEW on domain schemas (see README).

-- --- Metric views ---

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".revenue_analytics.metrics_sales_order TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".marketing_analytics.metrics_campaign_performance TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".manufacturing_analytics.metrics_production_execution TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_inventory_snapshot TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON VIEW " || {{catalog}} || ".supply_chain_analytics.metrics_supplier_quality TO `" || {{grant_group}} || "`";

-- --- Dim tables (entity names used by metric views / glossary links_to) ---

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_plant TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_production_line TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_part TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_warehouse TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_supplier TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_dealer TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_vehicle_model TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_campaign TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_channel TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".dim.dim_customer_segment TO `" || {{grant_group}} || "`";
