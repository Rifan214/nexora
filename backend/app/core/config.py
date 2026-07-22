from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = Field(default="Nexora Backend", alias="NEXORA_APP_NAME")
    api_version: str = Field(default="0.2.0", alias="NEXORA_API_VERSION")
    env: str = Field(default="development", alias="NEXORA_ENV")
    debug: bool = Field(default=False, alias="NEXORA_DEBUG")
    cors_origins: str = Field(default="", alias="NEXORA_CORS_ORIGINS")
    # Keep a longer safety cap for completed files that are never requested.
    download_expiration_minutes: int = Field(default=30, ge=1, alias="DOWNLOAD_EXPIRATION_MINUTES")
    # Once a client has received a file, retain the backend copy for a short
    # grace period in case it needs to retry the transfer.
    temp_file_retention_minutes: int = Field(default=15, ge=0, alias="TEMP_FILE_RETENTION_MINUTES")
    # Failed artifacts are always deleted immediately. This controls how long
    # the failed job record remains available to clients during lazy cleanup.
    failed_download_retention_minutes: int = Field(
        default=0,
        ge=0,
        alias="FAILED_DOWNLOAD_RETENTION_MINUTES",
    )

    @property
    def cors_origin_list(self) -> list[str]:
        if not self.cors_origins.strip():
            return []
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
