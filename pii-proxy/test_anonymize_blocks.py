"""Tests for PII anonymization of tool_result, tool_use blocks and placeholder consistency."""
import pytest
from collections import defaultdict

from proxy import (
    anonymize_messages,
    anonymize_text,
    build_anonymization,
    detect_pii,
    deanonymize_text,
    _anonymize_text_shared,
    _anonymize_content_block,
    _anonymize_dict_strings,
    _deanonymize_dict_strings,
)


# ---------------------------------------------------------------------------
# tool_result anonymization
# ---------------------------------------------------------------------------

class TestToolResultAnonymization:
    """tool_result blocks should be anonymized."""

    def test_tool_result_string_content(self):
        """tool_result with plain string content containing PII."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "From: Jan Testák <jan.testak@example.com>\nSubject: Meeting",
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        content = anon_msgs[0]["content"][0]["content"]

        assert "jan.testak@example.com" not in content
        assert "Jan Testák" not in content
        assert "<EMAIL_ADDRESS_" in content
        assert "<PERSON_" in content
        assert len(mapping) >= 2

    def test_tool_result_nested_text_blocks(self):
        """tool_result with list of text blocks."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": [
                            {"type": "text", "text": "Email from: Jan Testák"},
                            {"type": "text", "text": "Phone: +420 700 000 001"},
                        ],
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        blocks = anon_msgs[0]["content"][0]["content"]

        assert "Jan Testák" not in blocks[0]["text"]
        assert "+420 700 000 001" not in blocks[1]["text"]
        assert "<PERSON_" in blocks[0]["text"]
        assert "<PHONE_NUMBER_" in blocks[1]["text"]

    def test_tool_result_with_image_passthrough(self):
        """Image blocks inside tool_result should pass through unchanged."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": [
                            {"type": "image", "source": {"data": "base64data"}},
                            {"type": "text", "text": "Caption by Jan Testák"},
                        ],
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        blocks = anon_msgs[0]["content"][0]["content"]

        # Image untouched
        assert blocks[0]["type"] == "image"
        assert blocks[0]["source"]["data"] == "base64data"
        # Text anonymized
        assert "Jan Testák" not in blocks[1]["text"]

    def test_tool_result_null_content(self):
        """tool_result with content=None should not crash."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": None,
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        assert anon_msgs[0]["content"][0]["content"] is None
        assert mapping == {}

    def test_tool_result_no_content_key(self):
        """tool_result without content key should not crash."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        assert "content" not in anon_msgs[0]["content"][0]

    def test_tool_result_is_error(self):
        """Error tool_result should still be anonymized (errors can contain PII)."""
        msgs = [
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "is_error": True,
                        "content": "User jan.testak@example.com not found",
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        content = anon_msgs[0]["content"][0]["content"]
        assert "jan.testak@example.com" not in content
        assert anon_msgs[0]["content"][0]["is_error"] is True


# ---------------------------------------------------------------------------
# tool_use anonymization
# ---------------------------------------------------------------------------

class TestToolUseAnonymization:
    """tool_use blocks in assistant messages should be anonymized."""

    def test_tool_use_simple_input(self):
        """tool_use with command string containing PII."""
        msgs = [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "exec",
                        "input": {
                            "command": "gog gmail search from:jan.testak@example.com"
                        },
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        cmd = anon_msgs[0]["content"][0]["input"]["command"]

        assert "jan.testak@example.com" not in cmd
        assert "<EMAIL_ADDRESS_" in cmd

    def test_tool_use_nested_input(self):
        """tool_use with nested dict/list input."""
        msgs = [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "send",
                        "input": {
                            "to": ["jan.testak@example.com", "petra.testova@example.com"],
                            "subject": "Meeting s Jan Testák",
                            "options": {"cc": "boss@example.com"},
                        },
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        inp = anon_msgs[0]["content"][0]["input"]

        assert "jan.testak@example.com" not in str(inp)
        assert "petra.testova@example.com" not in str(inp)
        assert "boss@example.com" not in str(inp)
        assert "Jan Testák" not in str(inp)

    def test_tool_use_non_string_values_passthrough(self):
        """Non-string values in tool_use input should pass through unchanged."""
        msgs = [
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "search",
                        "input": {"max_results": 10, "include_drafts": False, "query": None},
                    }
                ],
            }
        ]
        anon_msgs, mapping = anonymize_messages(msgs)
        inp = anon_msgs[0]["content"][0]["input"]

        assert inp["max_results"] == 10
        assert inp["include_drafts"] is False
        assert inp["query"] is None


# ---------------------------------------------------------------------------
# Placeholder consistency across blocks
# ---------------------------------------------------------------------------

class TestPlaceholderConsistency:
    """Same PII value must get the same placeholder across all blocks in a request."""

    def test_same_email_across_user_msg_and_tool_result(self):
        """Same email in user message and tool_result should have same placeholder."""
        msgs = [
            {"role": "user", "content": "Najdi emaily od jan.testak@example.com"},
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "From: jan.testak@example.com Subject: Hello",
                    }
                ],
            },
        ]
        anon_msgs, mapping = anonymize_messages(msgs)

        # Extract placeholder from user message
        user_text = anon_msgs[0]["content"]
        # Extract placeholder from tool_result
        tr_text = anon_msgs[1]["content"][0]["content"]

        # Find the email placeholder in both
        for ph, orig in mapping.items():
            if orig == "jan.testak@example.com":
                assert ph in user_text, f"Placeholder {ph} not in user message"
                assert ph in tr_text, f"Placeholder {ph} not in tool_result"
                break

    def test_different_people_get_different_placeholders(self):
        """Two different people in different blocks must NOT collide."""
        msgs = [
            {"role": "user", "content": "Porovnej emaily Petra Testová a Jan Testák"},
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "From: Jan Testák <jan@x.com>\nTo: Petra Testová <petra@x.com>",
                    }
                ],
            },
        ]
        anon_msgs, mapping = anonymize_messages(msgs)

        # All PII values in mapping must be unique (no collisions)
        values = list(mapping.values())
        assert len(values) == len(set(values)), f"Collision in mapping values: {mapping}"

        # Check that placeholders in both messages are consistent
        user_text = anon_msgs[0]["content"]
        tr_text = anon_msgs[1]["content"][0]["content"]

        for ph, orig in mapping.items():
            if orig == "Jan Testák" and ph.startswith("<PERSON_"):
                assert ph in tr_text, f"{ph} for 'Jan Testák' not in tool_result"
            if orig == "Petra Testová" and ph.startswith("<PERSON_"):
                assert ph in user_text or ph in tr_text

    def test_same_person_same_placeholder_across_many_messages(self):
        """Same person name in 3 different messages should always use same placeholder."""
        msgs = [
            {"role": "user", "content": "Co psal Jan Testák?"},
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "exec",
                        "input": {"command": "search Jan Testák"},
                    }
                ],
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "Jan Testák: Zítra v 10:00",
                    }
                ],
            },
        ]
        anon_msgs, mapping = anonymize_messages(msgs)

        # Find the placeholder for "Jan Testák"
        jan_ph = None
        for ph, orig in mapping.items():
            if orig == "Jan Testák":
                jan_ph = ph
                break
        assert jan_ph is not None, "Jan Testák not detected"

        # Must appear in all 3 messages
        assert jan_ph in anon_msgs[0]["content"]
        assert jan_ph in anon_msgs[1]["content"][0]["input"]["command"]
        assert jan_ph in anon_msgs[2]["content"][0]["content"]

    def test_no_placeholder_collision_bug(self):
        """Regression: without shared counters, different people in different
        blocks would both get <PERSON_1>, causing wrong de-anonymization."""
        msgs = [
            {"role": "user", "content": "Email od Petra Testová"},
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": "From: Jan Testák <jan@example.com>",
                    }
                ],
            },
        ]
        anon_msgs, mapping = anonymize_messages(msgs)

        # Must have distinct placeholders for different people
        person_phs = {ph: orig for ph, orig in mapping.items() if ph.startswith("<PERSON_")}
        assert len(person_phs) >= 2, f"Expected >=2 distinct person placeholders, got {person_phs}"

        # Each placeholder must map to a unique person
        persons = list(person_phs.values())
        assert len(persons) == len(set(persons)), f"Placeholder collision: {person_phs}"


# ---------------------------------------------------------------------------
# De-anonymization helpers
# ---------------------------------------------------------------------------

class TestDeanonymization:
    """De-anonymization helpers for response processing."""

    def test_deanonymize_dict_strings(self):
        mapping = {"<PERSON_1>": "Jan Testák", "<EMAIL_ADDRESS_1>": "jan@x.com"}
        obj = {
            "command": "send to <PERSON_1> at <EMAIL_ADDRESS_1>",
            "count": 5,
            "nested": {"name": "<PERSON_1>"},
            "list": ["<EMAIL_ADDRESS_1>", "literal"],
        }
        result = _deanonymize_dict_strings(obj, mapping)

        assert result["command"] == "send to Jan Testák at jan@x.com"
        assert result["count"] == 5
        assert result["nested"]["name"] == "Jan Testák"
        assert result["list"] == ["jan@x.com", "literal"]


# ---------------------------------------------------------------------------
# Backward compatibility
# ---------------------------------------------------------------------------

class TestBackwardCompatibility:
    """Existing text-only behavior must not change."""

    def test_text_only_messages(self):
        """Standard text messages should work as before."""
        msgs = [
            {"role": "user", "content": "Zavolej Jan Testák na +420 700 000 001"},
            {"role": "assistant", "content": "OK, volám."},
        ]
        anon_msgs, mapping = anonymize_messages(msgs)

        assert "Jan Testák" not in anon_msgs[0]["content"]
        assert "+420 700 000 001" not in anon_msgs[0]["content"]
        assert anon_msgs[1]["content"] == "OK, volám."

    def test_standalone_anonymize_text_unchanged(self):
        """anonymize_text() standalone (no shared state) should still work."""
        text = "Email: jan.testak@example.com"
        anon, mapping = anonymize_text(text)
        assert "jan.testak@example.com" not in anon
        assert "<EMAIL_ADDRESS_1>" in anon

    def test_messages_with_none_content(self):
        """Messages with content=None should pass through."""
        msgs = [{"role": "assistant", "content": None}]
        anon_msgs, mapping = anonymize_messages(msgs)
        assert anon_msgs[0]["content"] is None

    def test_empty_messages(self):
        anon_msgs, mapping = anonymize_messages([])
        assert anon_msgs == []
        assert mapping == {}


# ---------------------------------------------------------------------------
# Full integration scenario
# ---------------------------------------------------------------------------

class TestFullEmailScenario:
    """End-to-end: user asks for emails, tool returns data, consistency maintained."""

    def test_email_read_conversation(self):
        """Simulate a full email-reading conversation.

        Note: tool_result lines are structured so that capitalized words
        on adjacent lines (separated by \\n + spaces) are not merged into
        a single PERSON entity by the regex (\\s+ matches newlines too).
        """
        msgs = [
            # User asks about emails
            {"role": "user", "content": "Přečti emaily od jan.testak@example.com"},
            # LLM calls exec tool (de-anonymized in history)
            {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": "toolu_1",
                        "name": "exec",
                        "input": {"command": "gog gmail search from:jan.testak@example.com --max 5"},
                    }
                ],
            },
            # Tool result with email content (lowercase line starts to avoid
            # PERSON regex merging across newlines)
            {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": "toolu_1",
                        "content": (
                            "1) od jan.testak@example.com — schůzka\n"
                            "   Jan Testák: potvrzuji schůzku, tel +420 700 000 001\n"
                            "2) od jan.testak@example.com — faktura\n"
                            "   IČO: 12345678"
                        ),
                    }
                ],
            },
            # User follow-up
            {"role": "user", "content": "Shrň co psal Jan Testák"},
        ]

        anon_msgs, mapping = anonymize_messages(msgs)

        # 1. No raw PII should leak
        full_text = str(anon_msgs)
        assert "jan.testak@example.com" not in full_text
        assert "+420 700 000 001" not in full_text
        assert "12345678" not in full_text

        # 2. Email placeholder consistent across all messages
        email_ph = None
        for ph, orig in mapping.items():
            if orig == "jan.testak@example.com":
                email_ph = ph
                break
        assert email_ph is not None

        # Same placeholder in user msg, tool_use input, tool_result, and follow-up
        assert email_ph in anon_msgs[0]["content"]
        assert email_ph in anon_msgs[1]["content"][0]["input"]["command"]
        assert email_ph in anon_msgs[2]["content"][0]["content"]

        # 3. "Jan Testák" consistent (appears in tool_result and follow-up)
        jan_ph = None
        for ph, orig in mapping.items():
            if orig == "Jan Testák":
                jan_ph = ph
                break
        assert jan_ph is not None
        assert jan_ph in anon_msgs[2]["content"][0]["content"]
        assert jan_ph in anon_msgs[3]["content"]

        # 4. De-anonymization round-trip
        # Simulate LLM response using placeholders
        response_text = f"{jan_ph} psal o schůzce. Kontakt: {email_ph}"
        restored = deanonymize_text(response_text, mapping)
        assert "Jan Testák" in restored
        assert "jan.testak@example.com" in restored
