-- Grant SELECT on Phase 3 knowledge-graph tables (ontology.kg_nodes / kg_edges).
-- Job params: {{catalog}} and {{grant_group}} expand to quoted strings (e.g. 'gold_dev', 'users').
-- Principal matches bundle var genie_space_permission_group (same as grant_metric_views).
-- KG tables are not Genie data sources; grants allow SQL/notebook navigation only.

EXECUTE IMMEDIATE
"GRANT USAGE ON SCHEMA " || {{catalog}} || ".ontology TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".ontology.kg_nodes TO `" || {{grant_group}} || "`";

EXECUTE IMMEDIATE
"GRANT SELECT ON TABLE " || {{catalog}} || ".ontology.kg_edges TO `" || {{grant_group}} || "`";
