from __future__ import annotations

import logging
from logging.config import dictConfig


def configure_logging(*, debug: bool) -> None:
    level_name = "DEBUG" if debug else "INFO"

    dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {
                "standard": {
                    "format": "%(asctime)s | %(levelname)s | %(name)s | %(message)s",
                },
            },
            "handlers": {
                "default": {
                    "class": "logging.StreamHandler",
                    "formatter": "standard",
                    "level": level_name,
                },
            },
            "root": {
                "handlers": ["default"],
                "level": level_name,
            },
            "loggers": {
                "uvicorn": {
                    "handlers": ["default"],
                    "level": level_name,
                    "propagate": False,
                },
                "uvicorn.error": {
                    "handlers": ["default"],
                    "level": level_name,
                    "propagate": False,
                },
                "uvicorn.access": {
                    "handlers": ["default"],
                    "level": level_name,
                    "propagate": False,
                },
            },
        }
    )

    logging.getLogger(__name__).debug("Logging configured at %s level", level_name)