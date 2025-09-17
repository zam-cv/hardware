from sqlalchemy import Column, Integer, String, Float, DateTime, Index
from sqlalchemy.sql import func
from sqlalchemy.orm import declarative_base
from pydantic import BaseModel
from typing import Literal, Optional
from datetime import datetime

Base = declarative_base()

METRICS = "metrics"

SensorType = Literal["temperature", "humidity", "light"]
ResolutionType = Literal["raw", "hourly", "daily"]

class Metric(BaseModel):
    source: str
    sensor: SensorType
    value: float

class HistoryQuery(BaseModel):
    sensor: SensorType
    from_time: Optional[datetime] = None
    to_time: Optional[datetime] = None
    resolution: ResolutionType = "raw"
    limit: int = 1000

class MetricModel(Base):
    __tablename__ = METRICS

    id = Column(Integer, primary_key=True, index=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    source = Column(String, index=True)
    sensor = Column(String, index=True)
    value = Column(Float)

    __table_args__ = (
        Index('idx_sensor_timestamp', 'sensor', 'timestamp'),
        Index('idx_timestamp_sensor', 'timestamp', 'sensor'),
    )

    def __repr__(self):
        return f"<Metric(id={self.id}, source='{self.source}', sensor='{self.sensor}', value='{self.value}')>"
