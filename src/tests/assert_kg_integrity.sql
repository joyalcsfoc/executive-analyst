-- Verify ontology.kg_nodes / kg_edges (the Delta property graph, ABox) are
-- internally consistent with each other and with the TBox declared in
-- src/ontology/graph.yml. Complements src/ontology/kg_queries.sql, which is
-- for ad hoc neighborhood browsing, not automated gating.
-- Job param {{catalog}} expands to a quoted string (e.g. 'gold_dev').
--
-- Checks:
--   1. No orphan edges (src_id / dst_id must exist in kg_nodes).
--   2. No node_id duplicates (node_id is the graph's primary key).
--   3. Every edge `rel` is one declared in graph.yml.
--   4. Every edge's (src node_type, dst node_type) matches that rel's
--      domain/range in graph.yml (e.g. hasLine must be Plant -> ProductionLine).

-- --- Diagnostic (run ad hoc in the SQL editor; lists every violation, 0 rows = pass) ---

EXECUTE IMMEDIATE
"SELECT check_name, detail FROM (
  SELECT 'orphan_edge' AS check_name,
    concat_ws(' -> ', e.src_id, e.dst_id, e.rel) AS detail
  FROM " || {{catalog}} || ".ontology.kg_edges e
  LEFT JOIN " || {{catalog}} || ".ontology.kg_nodes s ON e.src_id = s.node_id
  LEFT JOIN " || {{catalog}} || ".ontology.kg_nodes d ON e.dst_id = d.node_id
  WHERE s.node_id IS NULL OR d.node_id IS NULL

  UNION ALL
  SELECT 'duplicate_node_id', node_id
  FROM " || {{catalog}} || ".ontology.kg_nodes
  GROUP BY node_id HAVING COUNT(*) > 1

  UNION ALL
  SELECT 'unknown_rel', rel
  FROM " || {{catalog}} || ".ontology.kg_edges
  WHERE rel NOT IN ('hasLine', 'produces', 'soldBy', 'stockedAt', 'supplies', 'runsOnChannel', 'runsOnSegment')
  GROUP BY rel

  UNION ALL
  SELECT 'domain_range_violation',
    concat_ws(' ', e.rel, ':', s.node_type, '->', d.node_type, '(', e.src_id, '->', e.dst_id, ')')
  FROM " || {{catalog}} || ".ontology.kg_edges e
  JOIN " || {{catalog}} || ".ontology.kg_nodes s ON e.src_id = s.node_id
  JOIN " || {{catalog}} || ".ontology.kg_nodes d ON e.dst_id = d.node_id
  WHERE (e.rel = 'hasLine' AND NOT (s.node_type = 'Plant' AND d.node_type = 'ProductionLine'))
     OR (e.rel = 'produces' AND NOT (s.node_type = 'ProductionLine' AND d.node_type = 'Model'))
     OR (e.rel = 'soldBy' AND NOT (s.node_type = 'Model' AND d.node_type = 'Dealer'))
     OR (e.rel = 'stockedAt' AND NOT (s.node_type = 'Part' AND d.node_type = 'Warehouse'))
     OR (e.rel = 'supplies' AND NOT (s.node_type = 'Supplier' AND d.node_type = 'Part'))
     OR (e.rel = 'runsOnChannel' AND NOT (s.node_type = 'Campaign' AND d.node_type = 'Channel'))
     OR (e.rel = 'runsOnSegment' AND NOT (s.node_type = 'Campaign' AND d.node_type = 'Segment'))
) ORDER BY check_name, detail";

-- --- Gate (run by the validate_metric_views job; fails the task on any violation) ---

EXECUTE IMMEDIATE
"WITH violations AS (
  SELECT 'orphan_edge' AS check_name
  FROM " || {{catalog}} || ".ontology.kg_edges e
  LEFT JOIN " || {{catalog}} || ".ontology.kg_nodes s ON e.src_id = s.node_id
  LEFT JOIN " || {{catalog}} || ".ontology.kg_nodes d ON e.dst_id = d.node_id
  WHERE s.node_id IS NULL OR d.node_id IS NULL

  UNION ALL
  SELECT 'duplicate_node_id'
  FROM " || {{catalog}} || ".ontology.kg_nodes
  GROUP BY node_id HAVING COUNT(*) > 1

  UNION ALL
  SELECT 'unknown_rel'
  FROM " || {{catalog}} || ".ontology.kg_edges
  WHERE rel NOT IN ('hasLine', 'produces', 'soldBy', 'stockedAt', 'supplies', 'runsOnChannel', 'runsOnSegment')

  UNION ALL
  SELECT 'domain_range_violation'
  FROM " || {{catalog}} || ".ontology.kg_edges e
  JOIN " || {{catalog}} || ".ontology.kg_nodes s ON e.src_id = s.node_id
  JOIN " || {{catalog}} || ".ontology.kg_nodes d ON e.dst_id = d.node_id
  WHERE (e.rel = 'hasLine' AND NOT (s.node_type = 'Plant' AND d.node_type = 'ProductionLine'))
     OR (e.rel = 'produces' AND NOT (s.node_type = 'ProductionLine' AND d.node_type = 'Model'))
     OR (e.rel = 'soldBy' AND NOT (s.node_type = 'Model' AND d.node_type = 'Dealer'))
     OR (e.rel = 'stockedAt' AND NOT (s.node_type = 'Part' AND d.node_type = 'Warehouse'))
     OR (e.rel = 'supplies' AND NOT (s.node_type = 'Supplier' AND d.node_type = 'Part'))
     OR (e.rel = 'runsOnChannel' AND NOT (s.node_type = 'Campaign' AND d.node_type = 'Channel'))
     OR (e.rel = 'runsOnSegment' AND NOT (s.node_type = 'Campaign' AND d.node_type = 'Segment'))
)
SELECT CASE WHEN COUNT(*) = 0
  THEN 'PASS: kg_nodes/kg_edges pass orphan, uniqueness, rel-vocabulary, and domain/range checks'
  ELSE raise_error(concat('FAIL: knowledge graph integrity violated: ', concat_ws(', ', collect_set(check_name))))
END AS result
FROM violations";
