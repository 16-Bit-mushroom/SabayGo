"""Application configuration.

Settings are validated at import time. A missing or malformed value stops
the process at startup rather than degrading silently at runtime -- the
same failure mode that let an empty API key produce twelve quiet 401s
during AI node testing.
"""

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )

    app_name: str = "SabayGo API"
    environment: str = Field(default="development")
    debug: bool = Field(default=True)

    # --- database -------------------------------------------------------
    database_url: str = Field(
        default="mysql+asyncmy://sabaygo_app:sabaygo_app_dev@127.0.0.1:3307/sabaygo"
    )
    db_pool_size: int = 20
    db_max_overflow: int = 10
    db_echo: bool = False

    # --- auth -----------------------------------------------------------
    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 12

    # --- AI node --------------------------------------------------------
    ai_node_url: str = "http://localhost:5000"
    ai_node_api_key: str | None = None
    ai_node_timeout_s: float = 20.0

    # --- payments -------------------------------------------------------
    paymongo_secret_key: str | None = None
    paymongo_webhook_secret: str | None = None
    # Where PayMongo sends the passenger after checkout. Deep link in
    # production; a plain page is fine for sandbox testing.
    payment_success_url: str = "http://localhost:8000/payments/success"
    payment_cancel_url: str = "http://localhost:8000/payments/cancel"

    cors_origins: list[str] = ["http://localhost:8080", "http://localhost:3000"]

    @field_validator("database_url")
    @classmethod
    def _must_be_async_driver(cls, v: str) -> str:
        if not v.startswith("mysql+asyncmy://"):
            raise ValueError(
                "database_url must use the asyncmy driver "
                "(mysql+asyncmy://...); a sync driver will block the event loop."
            )
        return v


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]


settings = get_settings()