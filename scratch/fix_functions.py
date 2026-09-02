"""Fix render_kg_functions: revert to EXECUTE IMMEDIATE but without doubling single quotes."""
from pathlib import Path

gen_path = Path(
    r"c:\Users\JoyalCS\OneDrive - Focaloid Technologies Private Limited"
    r"\Focaloid Project\Databricks\executive-analyst\src\ontology\generate.py"
)

src = gen_path.read_text(encoding="utf-8")

# Let's replace the render_kg_functions with the correct EXECUTE IMMEDIATE version.
# We need to use EXECUTE IMMEDIATE because Databricks job parameters like {{catalog}}
# resolve to string literals (e.g. 'gold_dev'), which can only be concatenated,
# not used as identifiers directly.
# BUT we don't need to double the single quotes if the outer string is double-quoted.

NEW_FUNC = '''def render_kg_functions(model: Model) -> str:
    rels = sorted({p.name for p in model.object_properties if p.edge_from})
    rel_list = ", ".join(f"'{r}'" for r in rels)
    return f"""-- Executive Analyst knowledge-graph traversal functions.
-- Register these as UC functions and add them as a Genie space "functions" data
-- source (or a Multi-Agent Supervisor tool) so the agent can answer relationship
-- questions the metric views cannot (no cross-domain join path at fact grain).
-- {GENERATED_BANNER}
-- Known rels materialized by materialize_kg.sql: {rel_list}

EXECUTE IMMEDIATE
"CREATE OR REPLACE FUNCTION " || {{{{catalog}}}} || ".ontology.kg_neighbors(
  node_type STRING COMMENT 'Ontology class, e.g. Plant, Part, Supplier',
  node_key STRING COMMENT 'Business key of the starting node',
  rel STRING DEFAULT NULL COMMENT 'Restrict to one relationship name; NULL returns all'
)
RETURNS TABLE (direction STRING, rel STRING, node_type STRING, node_key STRING, node_name STRING)
COMMENT 'One-hop neighbors of a knowledge-graph node in either direction, optionally filtered by relationship.'
RETURN
  SELECT 'out' AS direction, e.rel, e.object_type AS node_type, e.object_key AS node_key, n.node_name
  FROM " || {{{{catalog}}}} || ".ontology.kg_edges e
  JOIN " || {{{{catalog}}}} || ".ontology.kg_nodes n
    ON n.node_type = e.object_type AND n.node_key = e.object_key
  WHERE e.subject_type = node_type AND e.subject_key = node_key
    AND (rel IS NULL OR e.rel = rel)
  UNION ALL
  SELECT 'in' AS direction, e.rel, e.subject_type AS node_type, e.subject_key AS node_key, n.node_name
  FROM " || {{{{catalog}}}} || ".ontology.kg_edges e
  JOIN " || {{{{catalog}}}} || ".ontology.kg_nodes n
    ON n.node_type = e.subject_type AND n.node_key = e.subject_key
  WHERE e.object_type = node_type AND e.object_key = node_key
    AND (rel IS NULL OR e.rel = rel)";

EXECUTE IMMEDIATE
"CREATE OR REPLACE FUNCTION " || {{{{catalog}}}} || ".ontology.kg_find_node(
  search_name STRING COMMENT 'Business name or partial name to look up, e.g. a plant or supplier name'
)
RETURNS TABLE (node_type STRING, node_key STRING, node_name STRING)
COMMENT 'Resolve a business name to its knowledge-graph node(s) so kg_neighbors can be called on it.'
RETURN
  SELECT node_type, node_key, node_name
  FROM " || {{{{catalog}}}} || ".ontology.kg_nodes
  WHERE node_name ILIKE '%' || search_name || '%'";
"""
'''

# Find the start of def render_kg_functions and replace it entirely up to the next # --- line
start_idx = src.find("def render_kg_functions")
end_idx = src.find("# ---------------------------------------------------------------------------", start_idx)

if start_idx != -1 and end_idx != -1:
    src = src[:start_idx] + NEW_FUNC + src[end_idx:]
    gen_path.write_text(src, encoding="utf-8", newline="\n")
    print("Fixed render_kg_functions with proper EXECUTE IMMEDIATE string literals.")
else:
    print("Could not find bounds.")
