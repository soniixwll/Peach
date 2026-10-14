"""AWS Lambda entry point: the FastAPI app behind a Lambda function URL.

Three kinds of event arrive here:

- HTTP requests from the function URL (payload format 2.0), handed to the ASGI
  app through Mangum.
- ``{"action": "migrate"}``, sent by scripts/deploy-backend.sh through a direct
  invoke after every deploy.
- ``{"action": "seed_report_meetings", "week": "YYYY-Www"}``, sent only by
  the administrative seed script.

A function URL request cannot produce either administrative shape - its body
is nested under ``body``, not at the top level - so those paths are reachable
only by a principal allowed to call ``lambda:InvokeFunction`` directly.
"""

import asyncio
import logging
from pathlib import Path
from typing import Any

from mangum import Mangum

from app.main import app

logger = logging.getLogger(__name__)

ALEMBIC_INI = Path(__file__).resolve().parent.parent / "alembic.ini"

# Mangum calls asyncio.get_event_loop(), which on Python 3.14 raises when no
# loop is set. Own one loop for the life of the execution environment, and set
# it again before every call - alembic's asyncio.run() unsets it on exit.
_loop = asyncio.new_event_loop()
_asgi = Mangum(app, lifespan="off")


def _migrate() -> dict[str, str]:
    from alembic import command
    from alembic.config import Config

    config = Config(str(ALEMBIC_INI))
    config.set_main_option("script_location", str(ALEMBIC_INI.parent / "migrations"))
    command.upgrade(config, "head")
    logger.info("migrations applied")
    return {"status": "ok", "migrated_to": "head"}


def _seed_report_meetings(week: object) -> dict[str, Any]:
    from app.reports.seed import seed_report_meetings

    if not isinstance(week, str):
        raise ValueError("seed_report_meetings requires an ISO week string")
    asyncio.set_event_loop(_loop)
    result = _loop.run_until_complete(seed_report_meetings(week))
    logger.info(
        "report meeting seed completed",
        extra={
            "week": result["week"],
            "inserted": result["inserted"],
            "skipped": result["skipped"],
        },
    )
    return {"status": "ok", **result}


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    if event.get("action") == "migrate":
        return _migrate()
    if event.get("action") == "seed_report_meetings":
        return _seed_report_meetings(event.get("week"))
    asyncio.set_event_loop(_loop)
    return _asgi(event, context)
