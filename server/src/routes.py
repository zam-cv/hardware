import asyncio
from fastapi import APIRouter, WebSocket, Query
from typing import Optional
from database import Database
from models import Metric, MetricModel, SensorType
from ml_service import predict_sensor, clear_all_models, clear_sensor_model

router = APIRouter()

metrics_queue = asyncio.Queue()


@router.post("/metric", status_code=201)
async def create_metric(metric: Metric) -> dict:
    metric_model = MetricModel(
        source=metric.source,
        sensor=metric.sensor,
        value=metric.value,
    )

    metric_id = await Database.create_metric(metric_model)

    # Create serializable dict for WebSocket
    metric_data = {
        "id": str(metric_id),
        "source": metric.source,
        "sensor": metric.sensor,
        "value": metric.value,
        "timestamp": (
            metric_model.timestamp.isoformat() if metric_model.timestamp else None
        ),
    }

    await metrics_queue.put(metric_data)
    return {"id": metric_id}


@router.get("/metrics/history")
async def get_metrics_history(
    sensor: SensorType = Query(..., description="Sensor type"),
    from_time: Optional[str] = Query(None, description="Start time (ISO format)"),
    to_time: Optional[str] = Query(None, description="End time (ISO format)"),
    target_points: int = Query(
        60, description="Target number of points to return", le=500
    ),
):
    data = await Database.get_metrics_history(
        sensor=sensor, from_time=from_time, to_time=to_time, target_points=target_points
    )
    return {"data": data, "count": len(data)}


@router.websocket("/ws-metrics")
async def ws_metrics(websocket: WebSocket):
    await websocket.accept()
    while True:
        try:
            metric = await metrics_queue.get()
            await websocket.send_json(metric)
        except Exception:
            break


# ML Endpoints
@router.get("/predict/{sensor_type}")
async def predict_sensor_endpoint(
    sensor_type: str,
    horizons: Optional[str] = Query(
        None, description="Comma-separated horizons in minutes (e.g., '15,60,180')"
    ),
):
    if horizons:
        try:
            horizon_list = [int(h.strip()) for h in horizons.split(",")]
        except ValueError:
            return {"error": "Invalid horizons format. Use comma-separated integers."}
    else:
        horizon_list = [15, 60, 360, 1440]  # Default: 15min, 1h, 6h, 24h

    result = await predict_sensor(sensor_type, horizon_list)
    return result


@router.post("/models/clear")
async def clear_models_endpoint():
    clear_all_models()
    return {"message": "All models cleared successfully"}


@router.post("/models/clear/{sensor_type}")
async def clear_sensor_model_endpoint(sensor_type: str):
    clear_sensor_model(sensor_type)
    return {"message": f"Model for sensor {sensor_type} cleared successfully"}
