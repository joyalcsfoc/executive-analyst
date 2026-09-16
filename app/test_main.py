"""Self-check for the one piece of branching logic in the app.

    python app/test_main.py
"""

from types import SimpleNamespace as N

from main import pick_attachment


def att(text=None, query=None, attachment_id="a1"):
    return N(
        text=N(content=text) if text is not None else None,
        query=N(query=query, description="d") if query else None,
        attachment_id=attachment_id,
    )


def test():
    # Prose answer.
    m = N(attachments=[att(text="OEE was 72%")], content=None)
    assert pick_attachment(m) == {"kind": "text", "content": "OEE was 72%"}

    # SQL answer -- caller must fetch rows separately.
    m = N(attachments=[att(query="SELECT 1")], content=None)
    got = pick_attachment(m)
    assert got["kind"] == "query" and got["sql"] == "SELECT 1"

    # An empty text attachment must not shadow a real query attachment.
    m = N(attachments=[att(text=""), att(query="SELECT 2")], content=None)
    assert pick_attachment(m)["sql"] == "SELECT 2"

    # No attachments -- Genie refused or asked for clarification.
    m = N(attachments=[], content="Which cost do you mean?")
    assert pick_attachment(m) == {"kind": "empty", "content": "Which cost do you mean?"}

    print("ok")


if __name__ == "__main__":
    test()
