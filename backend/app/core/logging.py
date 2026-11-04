import logging
import json
from datetime import datetime, timezone


class _JsonFormatter(logging.Formatter):
    """Emit only fixed event metadata, avoiding arbitrary exception/request data."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "event": getattr(record, "event", "application_log"),
        }
        for key in ("method", "route"):
            value = getattr(record, key, None)
            if isinstance(value, str):
                payload[key] = value
        return json.dumps(payload, separators=(",", ":"))


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=level.upper(),
        handlers=[logging.StreamHandler()],
        force=True,
    )
    for handler in logging.getLogger().handlers:
        handler.setFormatter(_JsonFormatter())
