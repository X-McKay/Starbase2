"""Feedback polling records advisory evidence without dispatching work."""

import asyncio
import copy
from unittest.mock import AsyncMock

import pytest
from starbase_runtime import sdlc_feedback_runtime as runtime
from starbase_runtime.review import digest

HEAD = "a" * 40


def capture(comments=None):
    value = {
        "head": HEAD, "lifecycle": "open", "coverage": "complete", "comments": comments or [],
    }
    return value | {"digest": digest(value)}


@pytest.fixture
def poll(monkeypatch):
    parent: dict = {"id": "sdlc-test", "evidence": {"submitted": {"number": 1}}, "feedback": []}
    captured = capture()
    capture_mock = AsyncMock(return_value=captured)
    propose = AsyncMock()
    writes = []

    async def request(method, path, body):
        assert method == "POST" and path == "/internal/v7/missions/sdlc-test/feedback"
        writes.append(copy.deepcopy(body))
        parent["feedback"].append(body)
        return body

    monkeypatch.setattr(runtime.sdlc_feedback, "capture", capture_mock)
    monkeypatch.setattr(runtime.sdlc_feedback, "propose", propose)
    monkeypatch.setattr(runtime.sdlc_pilot, "contract", lambda _: {"editable_paths": ["source.py"]})
    monkeypatch.setattr(runtime, "request", request)
    return parent, captured, capture_mock, propose, writes


def test_empty_feedback_cheap_no_change_then_unchanged_skips_model(poll):
    parent, _, _, propose, writes = poll
    first = asyncio.run(runtime.poll_feedback(parent))
    assert first is not None
    assert first["proposal"]["output"]["state"] == "no-change"
    assert first["proposal"]["output"]["advisory"] is True
    assert asyncio.run(runtime.poll_feedback(parent)) is None
    assert len(writes) == 1
    propose.assert_not_called()


def test_changed_feedback_retains_model_result_once(poll):
    parent, _, capture_mock, propose, writes = poll
    captured = capture([{"id": "issue:1", "body": "Please change something", "state": "unknown"}])
    capture_mock.return_value = captured
    propose.return_value = {"role": "feedback", "output": {"state": "unknown", "advisory": True}}
    result = asyncio.run(runtime.poll_feedback(parent))
    assert result is not None
    assert result["proposal"] == propose.return_value
    assert result["digest"] == captured["digest"]
    assert asyncio.run(runtime.poll_feedback(parent)) is None
    assert propose.await_count == 1
    assert len(writes) == 1


@pytest.mark.parametrize("error", [TimeoutError(), ValueError("unavailable")])
def test_model_failure_becomes_unknown_and_is_not_repeated(poll, error):
    parent, _, capture_mock, propose, writes = poll
    capture_mock.return_value = capture([{"id": "issue:1", "body": "request", "state": "unknown"}])
    propose.side_effect = error
    result = asyncio.run(runtime.poll_feedback(parent))
    assert result is not None
    assert result["proposal"]["output"]["state"] == "unknown"
    assert result["proposal"]["output"]["paths"] == []
    assert result["proposal"]["error_type"] == type(error).__name__
    assert asyncio.run(runtime.poll_feedback(parent)) is None
    assert propose.await_count == 1
    assert len(writes) == 1


def test_retention_exhaustion_and_unpublished_parent_do_not_poll(poll):
    parent, _, capture_mock, propose, writes = poll
    parent["feedback"] = [{}] * 16
    assert asyncio.run(runtime.poll_feedback(parent)) is None
    parent["feedback"] = []
    parent["evidence"] = {}
    assert asyncio.run(runtime.poll_feedback(parent)) is None
    capture_mock.assert_not_called()
    propose.assert_not_called()
    assert not writes


def test_capture_transport_failure_never_calls_model_or_records_false_success(poll):
    parent, _, capture_mock, propose, writes = poll
    capture_mock.side_effect = RuntimeError("provider unavailable")
    with pytest.raises(RuntimeError, match="unavailable"):
        asyncio.run(runtime.poll_feedback(parent))
    propose.assert_not_called()
    assert not writes
