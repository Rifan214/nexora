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
    download_expiration_minutes: int = Field(default=30, ge=1, alias="DOWNLOAD_EXPIRATION_MINUTES")

    @property
    def cors_origin_list(self) -> list[str]:
        if not self.cors_origins.strip():
            return []
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
