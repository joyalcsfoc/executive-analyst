-- Key-resolved edge sources for the {{catalog}}.ontology.kg_* build.
-- Hand-written (like grant_kg.sql) — NOT generated from the TTL.
--
-- Why this file exists: ea:edgeFrom in exec_analyst.ttl names ONE relation plus two
-- key columns, so a relation whose authoritative source carries business IDs rather
-- than surrogate keys has nowhere to put the join. This resolves those IDs up front
-- and hands materialize_kg.sql a relation that already satisfies the contract.
--
-- Navigation only, per the ontology's own rule: keys and cardinality live here,
-- KPI math stays in metrics_*.
--
-- Must run BEFORE src/ontology/materialize_kg.sql — see resources/metric_views_job.yml.

EXECUTE IMMEDIATE "CREATE SCHEMA IF NOT EXISTS " || {{catalog}} || ".ontology";

-- One row per contracted (supplier, part) pair, keyed for kg_edges.
--
-- Contract-derived, not event-derived. The previous source for supplierSuppliesPart
-- was fact_supplier_quality — an inspection-grain fact — which silently narrowed the
-- relation to "supplies this part AND we have inspected it": 45 of 60 contracted
-- parts. Parts never inspected (e.g. Blower Motor P0071, Headrest Guide P0088) had a
-- preferred supplier on contract but no edge in the graph, so traversals reported
-- them as unsourced.
--
-- is_preferred is carried, never filtered on: multi-sourced parts must keep every
-- supplier (P0055 has three), and dropping the non-preferred rows would re-introduce
-- an incomplete relation with a different cause.
EXECUTE IMMEDIATE
"CREATE OR REPLACE VIEW " || {{catalog}} || ".ontology.part_supplier_sourcing AS
  SELECT
    s.SUPPLIER_KEY,
    p.PART_KEY,
    c.is_preferred
  FROM " || {{catalog}} || ".supply_chain_analytics.dim_supplier_contract c
  JOIN " || {{catalog}} || ".dim.dim_supplier s ON s.SUPPLIER_ID = c.supplier_id
  JOIN " || {{catalog}} || ".dim.dim_part p ON p.PART_ID = c.part_id";

-- Guard: every contract row must resolve to both surrogate keys.
--
-- assert_kg_integrity's empty_rel check only fires at zero edges, so it would not
-- notice this relation quietly shrinking again — which is exactly how the original
-- defect survived. An unresolvable part_id or supplier_id (dim reload lag, an ID
-- format change) silently drops edges through the inner joins above, so compare the
-- counts here and fail the run at the earliest point rather than shipping a
-- half-populated graph.
EXECUTE IMMEDIATE
"SELECT CASE WHEN v.n = c.n
  THEN concat('PASS: part_supplier_sourcing resolved all ', c.n, ' contract rows')
  ELSE raise_error(concat(
    'FAIL: part_supplier_sourcing resolved ', v.n, ' of ', c.n,
    ' contract rows — unresolvable part_id/supplier_id would silently drop kg_edges'))
END AS result
FROM (SELECT COUNT(*) AS n FROM " || {{catalog}} || ".ontology.part_supplier_sourcing) v
CROSS JOIN (SELECT COUNT(*) AS n FROM " || {{catalog}} || ".supply_chain_analytics.dim_supplier_contract) c";
