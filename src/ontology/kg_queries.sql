-- Phase 3 — neighborhood queries against ontology.kg_nodes / kg_edges
-- Not part of apply_metric_views. Run in SQL editor after apply-metrics.
-- Replace catalog gold_dev with gold for prod. Replace sample labels as needed.
-- Protégé + exec_analyst.ttl = TBox (types). These tables = ABox (instances).

-- ---------------------------------------------------------------------------
-- Sanity: counts by type / rel
-- ---------------------------------------------------------------------------
-- SELECT node_type, COUNT(*) AS n FROM gold_dev.ontology.kg_nodes GROUP BY node_type ORDER BY 1;
-- SELECT rel, COUNT(*) AS n FROM gold_dev.ontology.kg_edges GROUP BY rel ORDER BY 1;

-- Orphan edges (should return 0 rows)
-- SELECT e.*
-- FROM gold_dev.ontology.kg_edges e
-- LEFT JOIN gold_dev.ontology.kg_nodes s ON e.src_id = s.node_id
-- LEFT JOIN gold_dev.ontology.kg_nodes d ON e.dst_id = d.node_id
-- WHERE s.node_id IS NULL OR d.node_id IS NULL;

-- ---------------------------------------------------------------------------
-- 1-hop: plant → production lines (hasLine)
-- ---------------------------------------------------------------------------
SELECT
  p.node_id AS plant_id,
  p.label AS plant_name,
  p.average_oee,
  e.rel,
  l.node_id AS line_id,
  l.label AS line_name
FROM gold_dev.ontology.kg_nodes p
JOIN gold_dev.ontology.kg_edges e
  ON e.src_id = p.node_id AND e.rel = 'hasLine'
JOIN gold_dev.ontology.kg_nodes l
  ON l.node_id = e.dst_id
WHERE p.node_type = 'Plant'
-- AND p.label = 'Your Plant Name'
ORDER BY p.label, l.label
LIMIT 50;

-- ---------------------------------------------------------------------------
-- 2-hop: plant → line → model (hasLine + produces)
-- ---------------------------------------------------------------------------
SELECT
  p.label AS plant_name,
  l.label AS line_name,
  m.label AS model_name
FROM gold_dev.ontology.kg_nodes p
JOIN gold_dev.ontology.kg_edges e1
  ON e1.src_id = p.node_id AND e1.rel = 'hasLine'
JOIN gold_dev.ontology.kg_nodes l
  ON l.node_id = e1.dst_id
JOIN gold_dev.ontology.kg_edges e2
  ON e2.src_id = l.node_id AND e2.rel = 'produces'
JOIN gold_dev.ontology.kg_nodes m
  ON m.node_id = e2.dst_id
WHERE p.node_type = 'Plant'
ORDER BY plant_name, line_name, model_name
LIMIT 50;

-- ---------------------------------------------------------------------------
-- Part neighborhood: stockedAt warehouses + inbound supplies
-- ---------------------------------------------------------------------------
SELECT
  part.label AS part_name,
  part.stockout_risk,
  part.average_days_of_supply,
  e.rel,
  n.label AS neighbor_name,
  n.node_type
FROM gold_dev.ontology.kg_nodes part
JOIN gold_dev.ontology.kg_edges e
  ON (e.src_id = part.node_id AND e.rel = 'stockedAt')
  OR (e.dst_id = part.node_id AND e.rel = 'supplies')
JOIN gold_dev.ontology.kg_nodes n
  ON n.node_id = CASE
    WHEN e.src_id = part.node_id THEN e.dst_id
    ELSE e.src_id
  END
WHERE part.node_type = 'Part'
-- AND part.stockout_risk = 'HIGH'
ORDER BY part.label, e.rel, neighbor_name
LIMIT 50;

-- ---------------------------------------------------------------------------
-- Supplier → parts (supplies) with optional HIGH stockout on part
-- ---------------------------------------------------------------------------
SELECT
  s.label AS supplier_name,
  s.ppm,
  s.copq,
  p.label AS part_name,
  p.stockout_risk
FROM gold_dev.ontology.kg_nodes s
JOIN gold_dev.ontology.kg_edges e
  ON e.src_id = s.node_id AND e.rel = 'supplies'
JOIN gold_dev.ontology.kg_nodes p
  ON p.node_id = e.dst_id
WHERE s.node_type = 'Supplier'
ORDER BY s.ppm DESC NULLS LAST, part_name
LIMIT 50;

-- ---------------------------------------------------------------------------
-- Model → dealers (soldBy)
-- ---------------------------------------------------------------------------
SELECT
  m.label AS model_name,
  d.label AS dealer_name,
  d.total_revenue_ytd
FROM gold_dev.ontology.kg_nodes m
JOIN gold_dev.ontology.kg_edges e
  ON e.src_id = m.node_id AND e.rel = 'soldBy'
JOIN gold_dev.ontology.kg_nodes d
  ON d.node_id = e.dst_id
WHERE m.node_type = 'Model'
ORDER BY model_name, dealer_name
LIMIT 50;

-- ---------------------------------------------------------------------------
-- Campaign → channel / segment
-- ---------------------------------------------------------------------------
SELECT
  c.label AS campaign_name,
  c.weighted_roas,
  e.rel,
  n.label AS neighbor_name,
  n.node_type
FROM gold_dev.ontology.kg_nodes c
JOIN gold_dev.ontology.kg_edges e
  ON e.src_id = c.node_id AND e.rel IN ('runsOnChannel', 'runsOnSegment')
JOIN gold_dev.ontology.kg_nodes n
  ON n.node_id = e.dst_id
WHERE c.node_type = 'Campaign'
ORDER BY campaign_name, e.rel, neighbor_name
LIMIT 50;
