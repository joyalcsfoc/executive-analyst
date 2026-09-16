"""Gate 5 checks: what must be held, and what must survive untouched.

    python app/test_output.py

The PASS list is the important one. A grounding check that holds correct answers
is worse than no grounding check, because it gets disabled and then the real
ungrounded answer sails through. Genie rounds, formats INR as lakh and crore,
and sums the column it just returned -- none of that is a hallucination.
"""

from guards import check_output

# Shape-valid but fake Databricks PAT, assembled at runtime so secret scanners
# don't flag the literal.
FAKE_PAT = "dapi" + "0123456789abcdef" * 2


def q(description, rows, sql="SELECT 1 FROM gold.manufacturing_analytics.x"):
    return {"kind": "query", "sql": sql, "description": description, "rows": rows}


def text(content):
    return {"kind": "text", "content": content}


def test_holds_ungrounded_figures():
    # 88.2 is nowhere in the rows and is not a sum, average or row count.
    got = check_output(q("OEE was 88.2% last week.", [["72.43"], ["69.10"]]))
    assert got["kind"] == "held" and got["reason"] == "grounding", got
    assert "88.2" in got["message"]

    # A text-only answer has no rows at all, so a figure in it is unsourced.
    got = check_output(text("Average OEE across the plants was 74.6%."))
    assert got["kind"] == "held" and got["reason"] == "grounding", got


def test_allows_grounded_figures():
    rows = [["72.43219", "1500"], ["69.10441", "2300"]]

    # Rounded to one decimal by Genie -- the single most common true case.
    assert check_output(q("OEE was 72.4%.", rows))["kind"] == "query"
    # Rounded to zero decimals.
    assert check_output(q("OEE was about 72%.", rows))["kind"] == "query"
    # Exact cell.
    assert check_output(q("Output was 2300 units.", rows))["kind"] == "query"
    # Sum of a returned column.
    assert check_output(q("Total output was 3800 units.", rows))["kind"] == "query"
    # Average of a returned column.
    assert check_output(q("Average OEE was 70.77%.", rows))["kind"] == "query"
    # Row count.
    assert check_output(q("2 lines were below target.", rows))["kind"] == "query"


def test_allows_inr_formatting():
    rows = [["12034567"], ["450000"]]
    # The space instructions require lakh/crore formatting. The gate has to be
    # able to read its own product's output format.
    assert check_output(q("COPQ was Rs 1.2 crore.", rows))["kind"] == "query"
    assert check_output(q("COPQ was ₹1.2 crore.", rows))["kind"] == "query"
    assert check_output(q("The smaller supplier was at 4.5 lakh.", rows))["kind"] == "query"


def test_ignores_dates_years_and_identifiers():
    rows = [["72.4"]]
    # None of these numbers are claims about data, and holding on them would
    # make the gate fire on nearly every answer.
    for prose in [
        "OEE on line 3 was 72.4%.",
        "In 2026 OEE was 72.4%.",
        "As of 2026-08-31, OEE was 72.4%.",
        "Shift 2 on plant 4 reached 72.4%.",
        "Q3 OEE was 72.4%.",
        "Spec revision 4 applied; OEE was 72.4%.",
    ]:
        assert check_output(q(prose, rows))["kind"] == "query", prose


def test_percent_convention_either_way():
    # The view stores 0-100, but tolerate a 0-1 row rather than hold on it.
    assert check_output(q("Quality was 72.4%.", [["0.724"]]))["kind"] == "query"


def test_strips_hedged_causal_claims():
    rows = [["72.4"]]
    got = check_output(q("OEE was 72.4%. This is probably because of the changeover.", rows))
    assert got["kind"] == "query"
    assert "probably because" not in got["description"]
    assert "72.4" in got["description"]
    assert "Removed 1 sentence" in got["note"]


def test_keeps_hedges_and_causes_that_stand_alone():
    rows = [["72.4"]]
    # A hedge with no causal claim.
    got = check_output(q("OEE was 72.4%, which may be below target.", rows))
    assert "may be below target" in got["description"] and "note" not in got

    # A causal statement with no hedge -- the data may well establish it, and
    # stripping it would silently delete a real finding.
    got = check_output(q("OEE was 72.4%. Downtime fell because of the new tooling.", rows))
    assert "because of the new tooling" in got["description"] and "note" not in got


def test_holds_sensitive_output_without_echoing_it():
    got = check_output(text(f"Connect with {FAKE_PAT} to see more."))
    assert got["kind"] == "held" and got["reason"] == "sensitive"
    assert "dapi" not in str(got), "a hold must not echo the secret back"

    got = check_output(q("See warehouse-07.internal for the raw extract.", [["1"]]))
    assert got["kind"] == "held" and got["reason"] == "sensitive"
    assert "internal" not in str(got).replace("internal address", "")


def test_attaches_freshness():
    got = check_output(q("Output was 1 unit.", [["1"]]), "Manufacturing loads daily.")
    assert got["freshness"] == "Manufacturing loads daily."
    # Never silently claim currency that was not supplied.
    got = check_output(q("Output was 1 unit.", [["1"]]))
    assert "not verified" in got["freshness"]


def test_clarifications_pass_through():
    # Genie asking which cost the user meant has no figures and must not be held.
    got = check_output(text("Which cost do you mean - cost of poor quality or landed cost?"))
    assert got["kind"] == "text"


def test():
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("ok -- gate 5")


if __name__ == "__main__":
    test()
