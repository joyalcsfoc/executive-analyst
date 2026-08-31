-- Drop legacy mv_executive_* metric views after metrics_* replacements exist and are tagged.
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev'); concatenate into DDL.

EXECUTE IMMEDIATE
"DROP VIEW IF EXISTS " || {{catalog}} || ".revenue_analytics.mv_executive_revenue";

EXECUTE IMMEDIATE
"DROP VIEW IF EXISTS " || {{catalog}} || ".marketing_analytics.mv_executive_marketing";

EXECUTE IMMEDIATE
"DROP VIEW IF EXISTS " || {{catalog}} || ".manufacturing_analytics.mv_executive_manufacturing";

EXECUTE IMMEDIATE
"DROP VIEW IF EXISTS " || {{catalog}} || ".supply_chain_analytics.mv_executive_inventory";

EXECUTE IMMEDIATE
"DROP VIEW IF EXISTS " || {{catalog}} || ".supply_chain_analytics.mv_executive_supplier_quality";
