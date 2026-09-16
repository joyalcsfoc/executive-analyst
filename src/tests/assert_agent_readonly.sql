-- Prove the agent's service principal can only read (guardrail Gate 3).
-- Job params: {{catalog}} and {{agent_sp}} expand to quoted strings.
--
-- Asserts on GRANT METADATA rather than by attempting a write, on purpose.
-- An INSERT-and-expect-failure test has two problems here: a SQL task runs as the
-- job's run_as (a human with MANAGE), not as the agent, so the write would
-- succeed and the test would report the opposite of the truth; and Databricks SQL
-- has no way to catch the exception and turn "denied" into a pass.
-- Reading information_schema sidesteps both -- it is identity-independent, so it
-- is honest no matter who runs the job.
--
-- Catches the realistic regression: someone grants the SP ALL PRIVILEGES or MODIFY
-- to unblock themselves in a hurry, which is exactly how a read-only agent stops
-- being one. Two principals already hold ALL PRIVILEGES on gold_dev_analytics.

-- --- Diagnostic (run ad hoc; lists every non-read privilege, 0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT 'table' AS level, table_schema AS securable, table_name AS object, privilege_type
 FROM " || {{catalog}} || ".information_schema.table_privileges
 WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type <> 'SELECT'
 UNION ALL
 SELECT 'schema', schema_name, NULL, privilege_type
 FROM " || {{catalog}} || ".information_schema.schema_privileges
 WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type NOT IN ('USE SCHEMA', 'SELECT')
 UNION ALL
 SELECT 'catalog', catalog_name, NULL, privilege_type
 FROM " || {{catalog}} || ".information_schema.catalog_privileges
 WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type NOT IN ('USE CATALOG', 'SELECT')";

-- --- Assertion (fails the job if the agent holds any write privilege) ---

EXECUTE IMMEDIATE
"WITH violations AS (
  SELECT concat(table_schema, '.', table_name, ':', privilege_type) AS v
  FROM " || {{catalog}} || ".information_schema.table_privileges
  WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type <> 'SELECT'
  UNION ALL
  SELECT concat('schema ', schema_name, ':', privilege_type)
  FROM " || {{catalog}} || ".information_schema.schema_privileges
  WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type NOT IN ('USE SCHEMA', 'SELECT')
  UNION ALL
  SELECT concat('catalog ', catalog_name, ':', privilege_type)
  FROM " || {{catalog}} || ".information_schema.catalog_privileges
  WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type NOT IN ('USE CATALOG', 'SELECT')
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: agent principal holds read privileges only'
  ELSE raise_error(concat('FAIL: agent principal holds write privileges: ', concat_ws(', ', collect_set(v))))
END AS result
FROM violations";

-- --- Assertion (fails if the agent cannot read what it is supposed to) ---
-- The mirror of the above. Without it, revoking everything would make the
-- read-only test pass while the agent is dead -- green for the wrong reason.

EXECUTE IMMEDIATE
"WITH granted AS (
  SELECT concat(table_schema, '.', table_name) AS obj
  FROM " || {{catalog}} || ".information_schema.table_privileges
  WHERE grantee = '" || {{agent_sp}} || "' AND privilege_type = 'SELECT'
),
required AS (
  SELECT * FROM (VALUES
    ('revenue_analytics.metrics_sales_order'),
    ('marketing_analytics.metrics_campaign_performance'),
    ('manufacturing_analytics.metrics_production_execution'),
    ('supply_chain_analytics.metrics_inventory_snapshot'),
    ('supply_chain_analytics.metrics_supplier_quality')
  ) AS t(obj)
),
missing AS (SELECT obj FROM required EXCEPT SELECT obj FROM granted)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: agent principal can read all five metric views'
  ELSE raise_error(concat('FAIL: agent principal missing SELECT on: ', concat_ws(', ', collect_set(obj))))
END AS result
FROM missing";
