"""Gate 1: check the question before the agent thinks about it.

Every check is a pattern match, not a model call. A guardrail that costs a token
budget is one that gets turned off the first time latency matters, and these run
on every request including the ones that turn out to be junk.

check_input returns (category, message) to refuse, or None to let the question
through. It is pure and importable without workspace credentials, so the
red-team set in test_guards.py exercises the real rules rather than copies.

The sixth Gate 1 control -- "treat retrieved text as data, never as orders" --
is absent on purpose: nothing is retrieved yet. Genie returns rows, and rows are
not read back to the model. It lands with the document index, not before.

Bias throughout: under-block rather than over-block. This agent can only read
analytics, so a missed refusal is a boundary blurred, while a false refusal
breaks a real question -- and "why did line 3 stop" is a real question.
"""

import logging
import re

log = logging.getLogger("guardrails")

MAX_QUESTION_CHARS = 2000

SCOPE_LINE = (
    "I can answer questions about production, inventory, supplier quality, "
    "revenue and marketing."
)

# --- Secrets -----------------------------------------------------------------
# Checked first, and checked before anything is logged, so a pasted credential
# is refused without being written anywhere on the way past.

SECRET = [
    re.compile(r"\bdapi[0-9a-f]{32}\b", re.I),  # Databricks PAT
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),  # AWS access key id
    re.compile(r"\bsk-[A-Za-z0-9]{20,}\b"),  # OpenAI-style key
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),  # GitHub token
    re.compile(r"(?:password|passwd|pwd|api[_-]?key|secret|token)\s*[:=]\s*\S+", re.I),
    re.compile(r"://[^/\s:@]+:[^/\s:@]+@"),  # user:pass@host in a URL or JDBC string
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

# --- Injection and jailbreak -------------------------------------------------

INJECTION = [
    re.compile(r"\bignore\s+(?:all\s+|any\s+|the\s+)?(?:previous|prior|above|earlier)\b", re.I),
    re.compile(
        r"\b(?:disregard|forget|override)\s+(?:all\s+|your\s+|the\s+)?"
        r"(?:previous\s+|prior\s+)?(?:instruction|rule|prompt|guideline|direction)",
        re.I,
    ),
    re.compile(r"\b(?:system|initial|original|hidden)\s+prompt\b", re.I),
    re.compile(
        r"\b(?:reveal|show|print|repeat|output|display)\s+(?:me\s+)?(?:your|the)\s+"
        r"(?:instruction|prompt|rule|config|guideline)",
        re.I,
    ),
    re.compile(r"\byou\s+are\s+(?:now|no\s+longer)\b", re.I),
    re.compile(r"\b(?:pretend|act)\s+(?:you\s+are|as\s+if|as\s+a|like)\b", re.I),
    re.compile(r"\b(?:developer|god|dan)\s+mode\b", re.I),
    re.compile(r"\brole[\s-]?play\b", re.I),
    # An unbroken 40-char base64 run is an encoded payload; no English word and
    # no part or batch number in this catalog comes close to that length.
    re.compile(r"[A-Za-z0-9+/]{40,}={0,2}"),
]

# --- Dangerous operational instructions --------------------------------------
# Two-condition on purpose. A bare keyword list blocks "which lines stopped most
# often last month", which is exactly what this agent is for. A command verb has
# to open the question AND an operational object has to appear somewhere in it.

COMMAND_VERB = re.compile(
    r"^\s*(?:please\s+|now\s+|just\s+|can\s+you\s+|could\s+you\s+|i\s+want\s+you\s+to\s+)*"
    r"(?:stop|halt|shut\s*down|restart|reboot|set|change|adjust|raise|lower|increase|"
    r"decrease|override|bypass|disable|enable|release|reset|unlock|open|close)\b",
    re.I,
)

OPERATIONAL_OBJECT = re.compile(
    r"\b(?:line|machine|furnace|oven|press|robot|conveyor|valve|motor|equipment|"
    r"set\s*point|interlock|guard|hold|temperature|pressure|speed|feed\s*rate|"
    r"parameter|limit|work\s*order|schedule|shift)\b",
    re.I,
)

# Phrases with no analytics reading, so position does not matter. Deliberately
# excludes "emergency stop" and "e-stop": those are downtime reason codes here,
# and "how many e-stops last month" has to reach Genie.
DANGEROUS_PHRASE = [
    re.compile(r"\boverride\s+(?:the\s+|a\s+)?(?:interlock|safety|limit|lockout)", re.I),
    re.compile(r"\bbypass\s+(?:the\s+|a\s+)?(?:interlock|safety|lockout|guard|permit)", re.I),
    re.compile(r"\brelease\s+(?:the\s+|a\s+)?(?:hold|quarantine|lockout)\b", re.I),
]

# --- Safety topics (Gate 4) --------------------------------------------------
# Escalate, never answer. Paraphrasing a lockout procedure from memory is the
# failure that ends the programme, and a correct-sounding paraphrase is worse
# than a refusal because it gets followed.
#
# Two-condition again, and for the same reason as the dangerous check: "how many
# e-stops last month" is a downtime question this agent exists to answer, while
# "what's the e-stop procedure" is one it must not touch. The topic alone cannot
# decide -- the framing does.

# ponytail: replace with the named owner from docs/agent-authority.md once that
# document is signed. A pointer to a role is the minimum; a pointer to a person
# is what actually gets followed.
SAFETY_CONTACT = "your plant EHS lead and the approved work instruction"

SAFETY_TOPIC = re.compile(
    r"\b(?:lockout|tagout|loto|ppe|personal\s+protective|interlock|light\s+curtain|"
    r"machine\s+guard|robot\s+(?:cell|zone|envelope)|confined\s+space|hazardous|hazmat|"
    r"msds|safety\s+data\s+sheet|arc\s+flash|permit\s+to\s+work|evacuation|"
    r"emergency\s+(?:stop|shutdown|procedure)|e-?stop|fire\s+drill|first\s+aid)\b",
    re.I,
)

# Procedural framing. Deliberately excludes "how many" / "how often", which are
# the analytics forms of the same words.
PROCEDURAL = re.compile(
    r"\b(?:how\s+(?:do|does|should|can|would)\s+(?:i|we|you|they)|"
    r"what(?:'s| is| are)\s+the\s+(?:procedure|process|steps|rule|policy|requirement)|"
    r"steps?\s+to\b|procedure\s+for\b|do\s+i\s+need\s+to\b|"
    r"is\s+it\s+safe\s+to\b|safe\s+to\b|should\s+i\b|can\s+i\s+(?:safely\s+)?\w+|"
    r"walk\s+me\s+through|explain\s+how\s+to|what\s+do\s+i\s+do)\b",
    re.I,
)

# --- Scope -------------------------------------------------------------------
# ponytail: named-case blocklist, not a real classifier. A true allowlist needs a
# cheap model call and breaks bare follow-ups ("and last month?"). Upgrade when
# the refusal log shows out-of-scope questions getting through, not before --
# the fixed data surface means Genie has nothing to answer them with anyway.

OUT_OF_SCOPE = [
    re.compile(
        r"\b(?:write|generate|create|give\s+me)\s+(?:me\s+)?(?:some\s+|a\s+|an\s+)?"
        r"(?:python|javascript|java|bash|code|script|program|function|regex)\b",
        re.I,
    ),
    re.compile(r"\b(?:my|his|her|their)\s+(?:salary|appraisal|leave|bonus|manager|performance\s+review)\b", re.I),
    re.compile(r"\b(?:hr|leave|maternity|resignation|notice\s+period)\s+policy\b", re.I),
    re.compile(r"\b(?:write|compose)\s+(?:me\s+)?(?:a\s+)?(?:poem|song|story|joke|essay|email)\b", re.I),
    re.compile(r"\b(?:recipe\s+for|capital\s+of|translate\s+(?:this|the|to|into))\b", re.I),
    re.compile(r"\b(?:medical|legal|investment|financial)\s+advice\b", re.I),
]

MESSAGES = {
    "secret": (
        "That question contained something that looks like a credential, so I "
        "dropped it without sending or storing it. Rotate that credential now, "
        "then ask again without it."
    ),
    "injection": (
        "I can't act on instructions that try to change how I work. " + SCOPE_LINE
    ),
    "dangerous": (
        "I can't carry out operational commands. I have no authority to change "
        "anything on the floor -- I only read analytics. " + SCOPE_LINE
    ),
    "safety": (
        "That's a safety procedure question, and I don't answer those -- not even "
        "to summarise. Use the approved procedure and check with "
        f"{SAFETY_CONTACT}. I can tell you what the production data shows about "
        "these events (how often, which lines, which shifts), but not what to do."
    ),
    "scope": "That's outside what I cover. " + SCOPE_LINE,
    "empty": "Empty question.",
    "too_long": (
        f"Questions are capped at {MAX_QUESTION_CHARS} characters. Ask the "
        "specific question rather than pasting the source material."
    ),
}


# =============================================================================
# Gate 5: check the answer before the user sees it
# =============================================================================
# Every rule below leans the same way: a false hold is more expensive than a
# missed one, because a gate that holds good answers gets switched off in week
# two and then holds nothing at all. So the extraction is narrow and the
# matching is generous, and anything ambiguous is treated as grounded.

INTERNAL_HOST = re.compile(
    r"\b[\w-]+\.(?:internal|local|localdomain|corp|intranet|lan)\b"
    r"|\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b",
    re.I,
)

# A sentence is stripped only when it hedges AND claims a cause. "OEE may be
# below target" is a hedge with no claim; "OEE fell because of downtime" is a
# claim the data may well support. Only the combination -- a guess dressed as an
# explanation -- gets removed.
HEDGE = re.compile(
    r"\b(?:probabl|likel|presumabl|possibl|perhaps|maybe|may\b|might\b|could\b|"
    r"appears?\b|seems?\b|suggests?\b|indicates?\b|suspect)", re.I,
)
CAUSAL = re.compile(
    r"\b(?:because|due\s+to|caused\s+by|driven\s+by|owing\s+to|as\s+a\s+result\s+of|"
    r"attributable\s+to|explains?\b|reason\s+for|leads?\s+to|led\s+to)\b", re.I,
)

SENTENCE = re.compile(r"[^.!?]+[.!?]*")

# Scale words, because the space instructions format INR as lakh and crore. A
# grounding check that cannot read its own output format holds every rupee
# figure ever produced.
SCALE = {
    "crore": 1e7, "cr": 1e7, "lakh": 1e5, "lakhs": 1e5, "lac": 1e5,
    "million": 1e6, "mn": 1e6, "m": 1e6, "billion": 1e9, "bn": 1e9, "k": 1e3,
}

_FIGURE = re.compile(
    r"(?<![\w.])(?:₹|rs\.?\s*|inr\s*)?"
    r"(\d{1,3}(?:,\d{2,3})+(?:\.\d+)?|\d+(?:\.\d+)?)"
    r"\s*(crore|cr|lakhs|lakh|lac|million|mn|billion|bn|k|%|percent)?",
    re.I,
)

# Numbers that follow these words are identifiers, not figures: "line 3",
# "shift 2", "revision 4". Checked against the text immediately before a match.
_IDENTIFIER_CONTEXT = re.compile(
    r"\b(?:line|plant|shift|rev|revision|batch|lot|order|part|model|warehouse|"
    r"supplier|dealer|campaign|channel|segment|week|quarter|q|fy|top|bottom|"
    r"first|last|next|previous)\s*#?\s*$",
    re.I,
)

_DATE_LIKE = re.compile(r"\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4}")


def _figures(text: str):
    """Pull the numbers from an answer that are claims about the data.

    Skips dates, years and identifiers. Returns (stated_value, decimals, raw)
    where stated_value is scaled to the same units a row would hold.
    """
    out = []
    masked = _DATE_LIKE.sub(" ", text)  # dates are never figures to ground
    for m in _FIGURE.finditer(masked):
        digits, suffix = m.group(1), (m.group(2) or "").lower()
        if _IDENTIFIER_CONTEXT.search(masked[: m.start()]):
            continue
        plain = digits.replace(",", "")
        try:
            value = float(plain)
        except ValueError:
            continue
        # A bare four-digit number in 1900-2100 is a year far more often than a
        # figure, and holding an answer over "2026" would be absurd.
        if not suffix and "." not in plain and 1900 <= value <= 2100:
            continue
        decimals = len(plain.split(".")[1]) if "." in plain else 0
        scaled = value * SCALE.get(suffix, 1) if suffix in SCALE else value
        out.append((scaled, decimals, m.group(0).strip(), suffix))
    return out


def _row_values(rows):
    """Every number the query actually returned, plus the safe derivations.

    Column sums and the row count are included because Genie legitimately says
    "across the five plants, total output was X" where X is a sum of the column
    it just returned, and holding that would be a false positive on the most
    ordinary sentence in the product.
    """
    values, columns = set(), {}
    for row in rows or []:
        for i, cell in enumerate(row or []):
            if cell is None:
                continue
            try:
                v = float(str(cell).replace(",", ""))
            except (ValueError, TypeError):
                continue
            values.add(v)
            columns.setdefault(i, []).append(v)
    for col in columns.values():
        values.add(sum(col))
        values.add(sum(col) / len(col))  # a stated average of a returned column
    values.add(float(len(rows or [])))
    return values


def _grounded(stated, decimals, suffix, values):
    """True if a stated figure plausibly came from one of these row values."""
    candidates = [stated]
    if suffix in ("%", "percent"):
        # Tolerate either convention rather than guess which one the view uses.
        candidates += [stated / 100, stated * 100]
    for v in values:
        for c in candidates:
            if round(v, decimals) == round(c, decimals):
                return True
            # Relative tolerance carries the rounded-then-scaled cases:
            # "1.2 crore" stated from a row holding 12,034,567.
            if abs(v - c) <= 0.005 * max(abs(v), abs(c), 1.0):
                return True
    return False


def _strip_causal_guesses(text: str):
    """Remove sentences that guess at a cause. Returns (text, removed_count)."""
    kept, removed = [], 0
    for sentence in SENTENCE.findall(text):
        if sentence.strip() and HEDGE.search(sentence) and CAUSAL.search(sentence):
            removed += 1
            continue
        kept.append(sentence)
    return ("".join(kept).strip() or text.strip(), removed) if removed else (text, 0)


def check_output(answer: dict, freshness: str | None = None) -> dict:
    """Gate 5. Returns the answer to show, or a held answer explaining why not.

    Pure on purpose: freshness is passed in rather than queried here, so the
    whole gate stays testable without a workspace.
    """
    prose = answer.get("content") or answer.get("description") or ""
    rows = answer.get("rows")

    # Sensitive data first, and a hold here returns nothing from the draft --
    # echoing the offending text back is how a leak becomes two leaks.
    if _hits(SECRET, prose) or _hits(SECRET, answer.get("sql") or "") or INTERNAL_HOST.search(prose):
        log.warning("gate5 hold reason=sensitive")
        return {
            "kind": "held",
            "reason": "sensitive",
            "message": (
                "I found something in the draft answer that looks like a credential "
                "or an internal address, so I'm not showing it. This is a bug worth "
                "reporting rather than retrying."
            ),
        }

    prose, stripped = _strip_causal_guesses(prose)

    # Grounding. A text-only answer carries no rows, so any figure in it is
    # unsourced by construction -- that is the case this check exists for.
    values = _row_values(rows)
    unverified = [
        raw
        for stated, decimals, raw, suffix in _figures(prose)
        if not _grounded(stated, decimals, suffix, values)
    ]
    if unverified:
        log.warning("gate5 hold reason=grounding figures=%s", unverified)
        return {
            "kind": "held",
            "reason": "grounding",
            "unverified": unverified,
            "message": (
                "I can't show this answer because "
                + ", ".join(unverified[:5])
                + " did not come from the data the query returned. Rather than guess, "
                "I've stopped. Ask again more specifically, or report this."
            ),
            "sql": answer.get("sql"),
        }

    out = dict(answer)
    if prose and answer.get("content"):
        out["content"] = prose
    elif prose and answer.get("description"):
        out["description"] = prose
    if stripped:
        out["note"] = (
            f"Removed {stripped} sentence(s) that guessed at a cause the data "
            "does not establish."
        )
    out["freshness"] = freshness or "Load status not verified for this answer."
    return out


def _hits(patterns, text):
    return any(p.search(text) for p in patterns)


def check_input(question: str):
    """Screen a question. Returns (category, message) to refuse, or None to allow."""
    question = question.strip()

    if not question:
        return "empty", MESSAGES["empty"]

    # Before the length check: a 5000-character paste containing a key is still a
    # leaked key, and "too long" would send it to the log on its way to a 413.
    if _hits(SECRET, question):
        log.warning("gate1 block category=secret")  # never log the question itself
        return "secret", MESSAGES["secret"]

    if len(question) > MAX_QUESTION_CHARS:
        return _block("too_long", question)

    if _hits(INJECTION, question):
        return _block("injection", question)

    if _hits(DANGEROUS_PHRASE, question) or (
        COMMAND_VERB.match(question) and OPERATIONAL_OBJECT.search(question)
    ):
        return _block("dangerous", question)

    # After "dangerous": "bypass the interlock" is a refusal, not an escalation.
    if SAFETY_TOPIC.search(question) and PROCEDURAL.search(question):
        return _block("safety", question)

    if _hits(OUT_OF_SCOPE, question):
        return _block("scope", question)

    return None


def _block(category: str, question: str):
    # Truncated because the whole point of a block is that the input is hostile
    # or oversized; the first 200 characters are enough to triage it.
    log.warning("gate1 block category=%s question=%.200r", category, question)
    return category, MESSAGES[category]
