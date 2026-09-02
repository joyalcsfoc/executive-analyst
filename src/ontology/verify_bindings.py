#!/usr/bin/env python3
"""Verify every ea:bound* annotation in exec_analyst.ttl resolves against a live catalog.

test_generate.py checks that the model is internally consistent. It cannot know
whether `MEASURE(copq)` exists in the deployed view — only the warehouse knows.
That gap is not theoretical: the first run of this script found nine bindings
pointing at identifiers that do not exist, because the two supply_chain metric
views were rebuilt with Title Case names while the repo's .sql files still
declare snake_case ones.

Requires the databricks-sdk and a configured CLI profile:
    pip install databricks-sdk
    python src/ontology/verify_bindings.py --profile gold --catalog gold_dev
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate as gen  # noqa: E402

try:
    from databricks.sdk import WorkspaceClient
    from databricks.sdk.service.sql import StatementState
except ImportError as e:  # pragma: no cover
    raise SystemExit("databricks-sdk is required: pip install databricks-sdk") from e


def make_runner(profile: str, warehouse: str | None, catalog: str):
    w = WorkspaceClient(profile=profile)
    wh = warehouse or next(
        (x.id for x in w.warehouses.list() if x.id), None
    )
    if not wh:
        raise SystemExit("No SQL warehouse available; pass --warehouse-id")

    def run(sql: str):
        r = w.statement_execution.execute_statement(
            statement=sql, warehouse_id=wh, catalog=catalog, wait_timeout="50s"
        )
        while r.status.state in (StatementState.PENDING, StatementState.RUNNING):
            r = w.statement_execution.get_statement(r.statement_id)
        if r.status.state != StatementState.SUCCEEDED:
            return None
        return (r.result.data_array or []) if r.result else []

    return run, wh


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--profile", default="gold")
    ap.add_argument("--catalog", default="gold_dev")
    ap.add_argument("--warehouse-id", default=None)
    args = ap.parse_args()

    model = gen.load_model(gen.TTL_PATH)
    run, wh = make_runner(args.profile, args.warehouse_id, args.catalog)
    print(f"catalog={args.catalog} warehouse={wh}\n")

    failures: list[str] = []

    # --- every bound view exists, and every bound measure/field is one of its columns ---
    views = sorted({g.view for g in model.grains} | {k.view for k in model.kpis})
    columns: dict[str, set[str]] = {}
    for v in views:
        rows = run(f"DESCRIBE {args.catalog}.{v}")
        if rows is None:
            failures.append(f"metric view {v} does not exist or is not readable")
            columns[v] = set()
            continue
        columns[v] = {r[0] for r in rows}

    for k in model.kpis:
        if k.measure not in columns.get(k.view, set()):
            failures.append(f"KPI {k.name}: MEASURE({k.measure}) not found in {k.view}")
        if k.view_field and k.view_field not in columns.get(k.view, set()):
            failures.append(f"KPI {k.name}: field {k.view_field!r} not found in {k.view}")

    for e in model.entities:
        if e.view and e.field and e.field not in columns.get(e.view, set()):
            failures.append(f"entity {e.name}: field {e.field!r} not found in {e.view}")

    for en in model.enums:
        view = None
        for cand in views:
            if en.column and en.column.rsplit(".", 1)[0] in cand:
                view = cand
        # enum field bindings are optional; only check the ones that declare a view
        if getattr(en, "view", None) and getattr(en, "field", None):
            if en.field not in columns.get(en.view, set()):
                failures.append(f"enum {en.name}: field {en.field!r} not found in {en.view}")

    # --- every bound dim table exists, with its key and name columns ---
    for e in model.entities:
        rows = run(f"DESCRIBE {args.catalog}.{e.table}")
        if rows is None:
            failures.append(f"entity {e.name}: table {e.table} does not exist or is not readable")
            continue
        cols = {r[0].upper() for r in rows}
        if e.key_col.upper() not in cols:
            failures.append(f"entity {e.name}: key column {e.key_col} not in {e.table}")
        if e.name_col.upper() not in cols:
            failures.append(f"entity {e.name}: name column {e.name_col} not in {e.table}")

    # --- every enum's declared values are values the column actually holds ---
    for en in model.enums:
        if not en.column or en.column.count(".") != 2:
            continue
        schema_table, col = en.column.rsplit(".", 1)
        rows = run(f"SELECT DISTINCT {col} FROM {args.catalog}.{schema_table} WHERE {col} IS NOT NULL")
        if rows is None:
            failures.append(f"enum {en.name}: cannot read {en.column}")
            continue
        actual = {r[0] for r in rows}
        declared = set(en.values)
        for missing in sorted(actual - declared):
            failures.append(f"enum {en.name}: column holds {missing!r}, which the TTL does not declare")

    # --- the KG traversal functions exist and return rows for a real node ---
    for fn in ("kg_find_node", "kg_neighbors"):
        rows = run(
            f"SELECT COUNT(*) FROM {args.catalog}.information_schema.routines "
            f"WHERE routine_schema='ontology' AND routine_name='{fn}'"
        )
        if rows is None or not rows or rows[0][0] == "0":
            failures.append(f"function ontology.{fn} is not deployed")

    probe = run(
        f"SELECT COUNT(*) FROM {args.catalog}.ontology.kg_neighbors("
        f"(SELECT node_type FROM {args.catalog}.ontology.kg_nodes WHERE node_type='Plant' LIMIT 1),"
        f"(SELECT node_key FROM {args.catalog}.ontology.kg_nodes WHERE node_type='Plant' LIMIT 1))"
    )
    if probe is None or not probe or probe[0][0] == "0":
        failures.append(
            "kg_neighbors returned no rows for a Plant that has edges — "
            "check for parameter/column shadowing in the function body"
        )

    if failures:
        print(f"FAILED ({len(failures)}):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(
        f"OK  {len(model.kpis)} measures, {len(model.entities)} entities, "
        f"{len(model.enums)} enums and the KG functions all resolve in {args.catalog}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
