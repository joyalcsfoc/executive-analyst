"""Passthrough wrapper around the Executive Analyst Genie space.

Step 0 of the guardrail plan: no input or output checks live here yet. This
exists so the app -- and therefore its service principal -- is real, so the
Genie round-trip is proven, and so gates 1 and 5 have somewhere to be added.

The app SP is the identity that Phase 1 grants SELECT to and revokes writes
from. Until the prod Genie space ACL is narrowed to that SP alone, anything
added here is one URL away from being bypassed.
"""

import os
from functools import cache

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from guards import check_input, check_output

# Matches title in resources/executive_analyst.genie_space.yml.
SPACE_TITLE = "Executive Analyst"

app = FastAPI(title="Executive Analyst")


# Both cached and lazy so importing this module needs no workspace credentials,
# which is what lets test_main.py test the real functions instead of copies.
@cache
def client():
    from databricks.sdk import WorkspaceClient

    return WorkspaceClient()


@cache
def space_id() -> str:
    """Find the Genie space by title so dev and prod need no per-target config.

    Dev-mode bundles prefix the title ("[dev joyal] Executive Analyst"), so match
    on substring. Set GENIE_SPACE_ID to bypass this if the match is ever wrong.
    """
    override = os.environ.get("GENIE_SPACE_ID")
    if override:
        return override
    spaces = client().genie.list_spaces().spaces or []
    matches = [s for s in spaces if SPACE_TITLE in (s.title or "")]
    if len(matches) != 1:
        titles = [s.title for s in matches]
        raise RuntimeError(
            f"Expected exactly one Genie space matching {SPACE_TITLE!r}, found {titles}. "
            "Set GENIE_SPACE_ID to pin one."
        )
    return matches[0].space_id


def pick_attachment(message):
    """Reduce a Genie message to the one attachment worth returning.

    Genie answers either in prose or with a SQL query whose result has to be
    fetched separately. Kept pure so it is testable without a workspace.
    """
    for att in message.attachments or []:
        if att.text and att.text.content:
            return {"kind": "text", "content": att.text.content}
        if att.query:
            return {
                "kind": "query",
                "attachment_id": att.attachment_id,
                "sql": att.query.query,
                "description": att.query.description,
            }
    return {"kind": "empty", "content": message.content}


# Which gold schema a query touched, for the freshness line. Read off the SQL
# because the app has no other way to know which domain answered.
DOMAINS = {
    "manufacturing_analytics": "Manufacturing",
    "supply_chain_analytics": "Supply chain",
    "revenue_analytics": "Revenue",
    "marketing_analytics": "Marketing",
}


def freshness_line(sql: str | None) -> str:
    """State the load cadence of whichever domains the query touched.

    ponytail: cadence only -- this says how often the data loads, not when it
    last loaded successfully. The honest version is one cached MAX(date) per
    domain per hour, which needs the date column confirmed for all five views
    (only execution_date and inspection_date are confirmed today). Until then
    this claims nothing it cannot support: a stale pipeline would make a
    "loaded yesterday" claim a lie, which is the exact failure this gate exists
    to prevent.
    """
    if not sql:
        return "No query ran for this answer."
    touched = [name for schema, name in DOMAINS.items() if schema in sql]
    if not touched:
        return "Load status not verified for this answer."
    return (
        f"{' and '.join(touched)} analytics load daily and lag the shop floor by "
        "up to a day. Last successful load is not verified here -- check against "
        "the MES for anything time-critical."
    )


class Ask(BaseModel):
    question: str


@app.post("/ask")
def ask(body: Ask):
    question = body.question.strip()

    # Gate 1. A refusal is a 4xx so that blocks are unmistakable in the request
    # metrics rather than buried in 200s that happen to contain an apology.
    refusal = check_input(question)
    if refusal:
        category, message = refusal
        raise HTTPException(413 if category == "too_long" else 400, message)

    genie = client().genie
    message = genie.start_conversation_and_wait(space_id(), content=question)
    answer = pick_attachment(message)

    if answer["kind"] == "query":
        result = genie.get_message_query_result_by_attachment(
            space_id(), message.conversation_id, message.message_id, answer["attachment_id"]
        )
        answer["rows"] = result.statement_response.result.data_array

    # Gate 5. Returns either the answer or a "held" dict -- still a 200, because
    # a hold is a real answer about what could not be verified, not a failure of
    # the request.
    return check_output(answer, freshness_line(answer.get("sql")))


@app.get("/health")
def health():
    return {"status": "ok", "space_id": space_id()}
