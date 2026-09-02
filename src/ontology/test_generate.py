#!/usr/bin/env python3
"""Self-check for the ontology compiler. No network, no Databricks, no framework.

Run from the repo root:
    python src/ontology/test_generate.py

Guards the things that break silently. The worst of them is in render_kg: an
object property carrying ea:edgeFrom whose domain or range is not a bound
entity is skipped with a bare `continue`, so the relation vanishes from
kg_edges and nothing anywhere says so. Everything else here is a binding the
generated SQL assumes is present but never asserts.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate as gen  # noqa: E402

FAILURES: list[str] = []


def check(condition: bool, message: str) -> None:
    if not condition:
        FAILURES.append(message)


def main() -> int:
    model = gen.load_model(gen.TTL_PATH)
    entity_names = {e.name for e in model.entities}
    prop_names = {p.name for p in model.object_properties}
    concept_names = (
        entity_names
        | {k.name for k in model.kpis}
        | {e.name for e in model.enums}
        | {a.name for a in model.ambiguous}
    )

    # --- the model is not empty (a bad TTL edit can silently produce nothing) ---
    check(len(model.entities) >= 10, f"expected >=10 bound entities, got {len(model.entities)}")
    check(len(model.kpis) >= 15, f"expected >=15 KPIs, got {len(model.kpis)}")
    check(len(model.enums) >= 3, f"expected >=3 enums, got {len(model.enums)}")
    check(len(model.grains) == 5, f"expected 5 grain classes (one per domain), got {len(model.grains)}")

    # --- entities must be fully bound: kg_nodes SELECTs them by key and name ---
    for e in model.entities:
        check(bool(e.table), f"entity {e.name}: no ea:boundToTable")
        check(bool(e.key_col), f"entity {e.name}: no ea:boundToKeyColumn")
        check(bool(e.name_col), f"entity {e.name}: no ea:boundToNameColumn")

    # --- KPIs must bind to a governed measure, or the agent has no sanctioned math ---
    for k in model.kpis:
        check(bool(k.view), f"KPI {k.name}: no ea:boundToView")
        check(bool(k.measure), f"KPI {k.name}: no ea:boundToMeasure")
        for other in k.not_same_as:
            check(other in concept_names, f"KPI {k.name}: ea:notSameAs {other!r} is not a known concept")

    # --- edges: the silent-drop guard ---
    edge_props = [p for p in model.object_properties if p.edge_from]
    check(len(edge_props) >= 8, f"expected >=8 materializable edges, got {len(edge_props)}")
    for p in edge_props:
        check(bool(p.edge_subject_key), f"edge {p.name}: ea:edgeFrom without ea:edgeSubjectKey")
        check(bool(p.edge_object_key), f"edge {p.name}: ea:edgeFrom without ea:edgeObjectKey")
        check(
            p.domain_class in entity_names,
            f"edge {p.name}: domain {p.domain_class} is not a bound entity — "
            f"render_kg would drop this relation from kg_edges without a word",
        )
        check(
            p.range_class in entity_names,
            f"edge {p.name}: range {p.range_class} is not a bound entity — "
            f"render_kg would drop this relation from kg_edges without a word",
        )

    # --- inverses must point at properties that exist ---
    for p in model.object_properties:
        if p.inverse_of:
            check(p.inverse_of in prop_names, f"{p.name}: owl:inverseOf {p.inverse_of!r} is not declared")

    # --- enums carry the literal warehouse values the agent will filter on ---
    for e in model.enums:
        check(len(e.values) >= 2, f"enum {e.name}: fewer than 2 values")
        check(all(v.strip() for v in e.values), f"enum {e.name}: an individual has a blank rdfs:label")

    # --- ambiguous terms must offer a real choice, all of them resolvable ---
    for a in model.ambiguous:
        check(len(a.disambiguates_to) >= 2, f"ambiguous term {a.name}: needs >=2 senses to be ambiguous")
        for target in a.disambiguates_to:
            check(target in concept_names, f"ambiguous term {a.name}: {target!r} is not a known concept")

    # --- rendering must not raise, and must leave no placeholder behind ---
    kg_sql = gen.render_kg(model)
    tags_sql = gen.render_tags(model)  # raises if a view lacks domain/grain tags
    check("{source}" not in kg_sql, "materialize_kg.sql still contains an unsubstituted {source} placeholder")

    # every declared edge actually reaches the SQL
    for p in edge_props:
        check(f"'{p.name}' AS rel" in kg_sql, f"edge {p.name}: declared in the TTL but absent from kg_edges SQL")
    for e in model.entities:
        check(f"'{e.name}' AS node_type" in kg_sql, f"entity {e.name}: bound in the TTL but absent from kg_nodes SQL")
        check(e.table in tags_sql, f"entity {e.name}: table {e.table} never tagged")

    # --- generated files on disk match the TTL (same contract as --check) ---
    outputs = {
        gen.OUT_TAGS: tags_sql,
        gen.OUT_KG: kg_sql,
        gen.OUT_GRANT_KG: gen.render_grant_kg(),
        gen.OUT_KG_FUNCTIONS: gen.render_kg_functions(model),
        gen.OUT_KG_QUERIES: gen.render_kg_queries(model),
        gen.OUT_HTML: gen.render_html(model),
        gen.OUT_GENIE_CTX: gen.render_genie_context(model),
        gen.OUT_KG_INTEGRITY: gen.render_kg_integrity(model),
        gen.OUT_GENIE_SPACE: gen.render_genie_space(model),
    }
    for path, content in outputs.items():
        check(path.is_file(), f"{path.name}: never generated")
        if path.is_file():
            check(
                path.read_text(encoding="utf-8") == content,
                f"{path.name}: stale — run python src/ontology/generate.py",
            )

    if FAILURES:
        print(f"FAILED ({len(FAILURES)}):", file=sys.stderr)
        for f in FAILURES:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"OK  {len(model.entities)} entities, {len(model.kpis)} KPIs, {len(model.enums)} enums, "
        f"{len(edge_props)} materializable edges, {len(outputs)} generated artifacts in sync"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
