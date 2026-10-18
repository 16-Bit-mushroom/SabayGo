"""Async database engine and session management."""

from collections.abc import AsyncGenerator

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import settings
from app.core.exceptions import ConflictError

engine = create_async_engine(
    settings.database_url,
    echo=settings.db_echo,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    # Recycle below MySQL's 8h wait_timeout so long-idle connections don't
    # surface as "server has gone away" mid-request.
    pool_recycle=3600,
    pool_pre_ping=True,
)

SessionFactory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency yielding a session with request-scoped transaction.

    Commit is explicit in the use case, not here -- a use case that needs
    to roll back partway through must be able to, and an implicit commit
    on teardown would defeat that.
    """
    async with SessionFactory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def commit_or_conflict(session: AsyncSession, message: str) -> None:
    """Commit, turning a unique-key race the pre-checks could not see into
    a 409 with `message` instead of a 500."""
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise ConflictError(message) from None
