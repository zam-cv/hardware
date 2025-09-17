import logging
import asyncio
from typing import Optional
from models import MetricModel, Base
from sqlalchemy import text, select
from datetime import datetime, timezone, timedelta
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    create_async_engine,
    AsyncSession,
    async_sessionmaker,
)

logger = logging.getLogger(__name__)


class Instance:
    def __init__(
        self, engine: AsyncEngine, session_factory: async_sessionmaker[AsyncSession]
    ):
        self.engine = engine
        self.session_factory = session_factory


class Database:
    _instance: Optional[Instance] = None

    @staticmethod
    def initialize(connection_string: str):
        if Database._instance is None:
            Database._instance = Database._create_instance(connection_string)

    @staticmethod
    def _create_instance(connection_string: str):
        engine = create_async_engine(
            connection_string,
            pool_size=10,
            max_overflow=0,
            pool_pre_ping=True,
            echo=False,
        )
        session_factory = async_sessionmaker(
            engine, class_=AsyncSession, expire_on_commit=False
        )
        return Instance(engine, session_factory)

    @staticmethod
    async def wait_for_connection():
        if Database._instance is None:
            raise Exception(
                "Database not initialized. Call Database.initialize() first."
            )

        while True:
            try:
                async with Database._instance.engine.begin() as conn:
                    await conn.execute(text("SELECT 1"))
                logger.info("Database connection established.")
                break
            except Exception as e:
                logger.info(f"Waiting for database connection... ({e})")
                await asyncio.sleep(1)

    @staticmethod
    async def create_tables():
        if Database._instance is None:
            raise Exception(
                "Database not initialized. Call Database.initialize() first."
            )

        async with Database._instance.engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    @staticmethod
    async def cleanup():
        if Database._instance is None:
            raise Exception(
                "Database not initialized. Call Database.initialize() first."
            )

        await Database._instance.engine.dispose()

    @staticmethod
    def get_session() -> AsyncSession:
        if Database._instance is None:
            raise Exception(
                "Database not initialized. Call Database.initialize() first."
            )

        return Database._instance.session_factory()

    @staticmethod
    async def create_metric(metric: MetricModel) -> int:
        async with Database.get_session() as session:
            session.add(metric)
            await session.commit()
            await session.refresh(metric)
            return metric.id

    @staticmethod
    async def get_metrics_history(
        sensor: str,
        from_time: Optional[str] = None,
        to_time: Optional[str] = None,
        target_points: int = 60,
    ):
        async with Database.get_session() as session:
            # Always use minute-based aggregation with automatic interval calculation
            return await Database._get_minute_aggregated_metrics(
                session, sensor, from_time, to_time, target_points
            )

    @staticmethod
    async def _get_minute_aggregated_metrics(
        session, sensor, from_time, to_time, target_points
    ):
        # Determine time range - ensure all dates have timezone
        now = datetime.now(timezone.utc)
        
        if to_time is None:
            to_dt = now
        else:
            to_dt = datetime.fromisoformat(to_time.replace("Z", "+00:00"))
            if to_dt.tzinfo is None:
                to_dt = to_dt.replace(tzinfo=timezone.utc)

        if from_time is None:
            # Default to last 6 hours if no from_time specified
            from_dt = now - timedelta(hours=6)
            from_dt = from_dt.replace(minute=0, second=0, microsecond=0)
        else:
            from_dt = datetime.fromisoformat(from_time.replace("Z", "+00:00"))
            if from_dt.tzinfo is None:
                from_dt = from_dt.replace(tzinfo=timezone.utc)

        # Calculate total time in minutes
        total_minutes = int((to_dt - from_dt).total_seconds() / 60)

        if total_minutes <= 0:
            return []

        # Calculate interval in minutes for aggregation
        interval_minutes = max(1, total_minutes // target_points)

        time_buckets = []
        current_time = from_dt.replace(second=0, microsecond=0)

        while current_time <= to_dt:
            time_buckets.append(current_time)
            current_time = current_time + timedelta(minutes=interval_minutes)

        # Query data and aggregate by calculated intervals
        base_query = (
            select(
                MetricModel.timestamp,
                MetricModel.value,
                MetricModel.sensor,
                MetricModel.source,
            )
            .filter(
                MetricModel.sensor == sensor,
                MetricModel.timestamp >= from_dt,
                MetricModel.timestamp <= to_dt,
            )
            .order_by(MetricModel.timestamp)
        )

        result = await session.execute(base_query)
        all_data = result.fetchall()

        if not all_data:
            return []

        # Create time buckets covering the REQUESTED range (not just data range)
        # This ensures data is distributed correctly across the requested time period
        bucket_duration_minutes = max(1, total_minutes // target_points)
        
        aggregated_data = []
        current_bucket_start = from_dt.replace(second=0, microsecond=0)
        
        while current_bucket_start < to_dt:
            bucket_end = current_bucket_start + timedelta(minutes=bucket_duration_minutes)
            
            # Find data points in this time bucket
            bucket_data = [
                row for row in all_data 
                if current_bucket_start <= row[0] < bucket_end
            ]
            
            if bucket_data:
                # Calculate average value for this bucket
                avg_value = sum(row[1] for row in bucket_data) / len(bucket_data)
                aggregated_data.append({
                    "timestamp": current_bucket_start.isoformat(),
                    "value": float(avg_value),
                    "sensor": sensor,
                    "source": bucket_data[0][3],
                })
            # Note: We don't add empty buckets - frontend will handle gaps
            
            current_bucket_start = bucket_end

        # Sort by timestamp (oldest first)
        aggregated_data.sort(key=lambda x: x["timestamp"])

        return aggregated_data
