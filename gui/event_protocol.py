from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any

GUI_EVENT_PREFIX = "__FX_GUI_EVENT__"


@dataclass
class GuiEvent:
    name: str
    payload: dict[str, Any]


def parse_gui_event_line(raw_line: str) -> GuiEvent | None:
    line = raw_line.strip()
    if not line or not line.startswith(GUI_EVENT_PREFIX):
        return None

    json_payload = line[len(GUI_EVENT_PREFIX) :].strip()
    if not json_payload:
        return None

    data = json.loads(json_payload)
    if not isinstance(data, dict):
        return None

    event_name = data.get("event")
    if not isinstance(event_name, str) or not event_name:
        return None

    payload = dict(data)
    payload.pop("event", None)
    return GuiEvent(name=event_name, payload=payload)
