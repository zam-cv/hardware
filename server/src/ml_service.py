import numpy as np
import pandas as pd
from datetime import datetime, timezone, timedelta
from typing import List, Dict, Optional
import logging
import lightgbm as lgb
from database import Database

logger = logging.getLogger(__name__)


class SensorModel:
    def __init__(self, sensor_id: str):
        self.sensor_id = sensor_id
        self.model = None
        self.last_training = None
        self.retrain_hours = 6  # Retrain every 6 hours
        self.min_points = 10  # Min points to train

    async def predict(self, horizons: List[int] = [15, 60, 360, 1440]) -> Dict:
        """Predict for this sensor at given horizons (minutes)"""
        try:
            # Train model if needed
            await self._train_if_needed()

            if self.model is None:
                return {"error": "Model not ready", "sensor": self.sensor_id}

            # Get recent data
            data = await self._get_recent_data()

            if len(data) < 5:
                return {
                    "error": f"Need more data. Have {len(data)} points",
                    "sensor": self.sensor_id,
                }

            # Make predictions
            predictions = {}
            now = datetime.now(timezone.utc)

            for minutes in horizons:
                features = self._create_prediction_features(data, minutes)
                pred_value = self.model.predict([features])[0]

                predictions[f"{minutes}min"] = {
                    "value": round(float(pred_value), 2),
                    "timestamp": (now + timedelta(minutes=minutes)).isoformat(),
                    "confidence": self._calculate_confidence(data, pred_value),
                }

            return {
                "sensor": self.sensor_id,
                "predictions": predictions,
                "model_trained": (
                    self.last_training.isoformat() if self.last_training else None
                ),
            }

        except Exception as e:
            logger.error(f"Prediction error for {self.sensor_id}: {e}")
            return {"error": str(e), "sensor": self.sensor_id}

    async def _train_if_needed(self):
        """Check if retraining is needed"""
        now = datetime.now(timezone.utc)

        needs_training = (
            self.model is None
            or self.last_training is None
            or (now - self.last_training).total_seconds() > self.retrain_hours * 3600
        )

        if needs_training:
            await self._train_model()

    async def _train_model(self):
        """Train LightGBM model for this sensor only"""
        try:
            logger.info(f"Training model for {self.sensor_id}")

            # Get training data (last 3 days)
            data = await self._get_data(hours=72)

            if len(data) < self.min_points:
                logger.warning(f"Not enough data for {self.sensor_id}: {len(data)}")
                return

            # Prepare features and targets
            X, y = self._prepare_training_data(data)

            if len(X) < 10:
                logger.warning(f"Not enough features for {self.sensor_id}")
                return

            # Train/validation split
            split_idx = int(len(X) * 0.8)

            # LightGBM training
            train_data = lgb.Dataset(X[:split_idx], label=y[:split_idx])
            val_data = lgb.Dataset(
                X[split_idx:], label=y[split_idx:], reference=train_data
            )

            params = {
                "objective": "regression",
                "metric": "rmse",
                "num_leaves": 31,  # Increased for more complexity
                "learning_rate": 0.05,  # Reduced for better learning
                "min_data_in_leaf": 3,  # Reduced to allow more granular splits
                "feature_fraction": 0.8,  # Random feature sampling
                "bagging_fraction": 0.8,  # Random data sampling
                "bagging_freq": 5,  # Frequency of bagging
                "max_depth": 6,  # Limit tree depth
                "lambda_l1": 0.1,  # L1 regularization
                "lambda_l2": 0.1,  # L2 regularization
                "verbose": -1,
            }

            self.model = lgb.train(
                params,
                train_data,
                num_boost_round=100,  # Increased training rounds
                valid_sets=[val_data],
                callbacks=[lgb.early_stopping(15), lgb.log_evaluation(0)],
            )

            self.last_training = datetime.now(timezone.utc)
            logger.info(f"Model trained for {self.sensor_id} with {len(X)} samples")

        except Exception as e:
            logger.error(f"Training error for {self.sensor_id}: {e}")

    def _prepare_training_data(self, data: List[Dict]):
        """Create features and targets from raw timestamp + value data"""
        df = pd.DataFrame(data)
        df["timestamp"] = pd.to_datetime(df["timestamp"])
        df = df.sort_values("timestamp").reset_index(drop=True)

        features = []
        targets = []

        # Create sliding window
        for i in range(5, len(df)):  # Need 5 previous points for features
            try:
                # Get previous values and timestamps
                prev_values = df.iloc[i - 5 : i]["value"].values
                prev_times = df.iloc[i - 5 : i]["timestamp"]
                current_time = df.iloc[i]["timestamp"]
                target_value = df.iloc[i]["value"]

                # Create feature vector
                feature_vec = self._create_features_from_data(
                    prev_values, prev_times, current_time
                )

                features.append(feature_vec)
                targets.append(target_value)

            except Exception:
                continue

        return np.array(features), np.array(targets)

    def _create_features_from_data(
        self, prev_values: np.ndarray, prev_times: pd.Series, current_time: pd.Timestamp
    ) -> List[float]:
        """Create features from historical data"""
        features = []

        # Lag features (previous values)
        if len(prev_values) >= 5:
            features.extend(prev_values.tolist()[-5:])  # Last 5 values
        else:
            # Pad with the last available value if not enough data
            padded_values = prev_values.tolist() + [prev_values[-1]] * (
                5 - len(prev_values)
            )
            features.extend(padded_values[-5:])

        # Statistical features
        features.append(np.mean(prev_values))
        features.append(np.std(prev_values))
        features.append(np.median(prev_values))
        features.append(np.max(prev_values) - np.min(prev_values))  # Range
        features.append(
            prev_values[-1] - prev_values[-2] if len(prev_values) > 1 else 0
        )  # Last change
        features.append(prev_values[-1] - np.mean(prev_values))  # Deviation from mean

        # Trend features
        if len(prev_values) >= 3:
            # Simple linear trend
            x = np.arange(len(prev_values))
            slope = np.polyfit(x, prev_values, 1)[0]
            features.append(slope)
        else:
            features.append(0)

        # Sensor-specific features (hash of sensor_id for uniqueness)
        sensor_hash = hash(self.sensor_id)
        features.append((sensor_hash % 1000) / 1000.0)  # Normalize hash

        # Time features
        features.append(current_time.hour)
        features.append(current_time.weekday())
        features.append(current_time.minute / 60.0)  # Normalize minutes

        # Time since last measurement (in hours)
        if len(prev_times) > 0:
            time_diff = (current_time - prev_times.iloc[-1]).total_seconds() / 3600
            features.append(min(time_diff, 24))  # Cap at 24 hours
        else:
            features.append(1)

        return features

    def _create_prediction_features(
        self, data: List[Dict], minutes_ahead: int
    ) -> List[float]:
        """Create features for prediction"""
        if len(data) < 3:
            return [0] * 16  # Updated to match new feature count

        # Get recent values and times
        recent_data = data[-5:]  # Last 5 points
        values = np.array([d["value"] for d in recent_data])

        # Prediction time
        pred_time = datetime.now(timezone.utc) + timedelta(minutes=minutes_ahead)

        features = []

        # Use last 5 values as lags (more historical context)
        if len(values) >= 5:
            features.extend(values[-5:].tolist())
        else:
            # Pad with the last available value if not enough data
            padded_values = values.tolist() + [values[-1]] * (5 - len(values))
            features.extend(padded_values[-5:])

        # Statistical features
        features.append(np.mean(values))
        features.append(np.std(values))
        features.append(np.median(values))
        features.append(np.max(values) - np.min(values))  # Range
        features.append(
            values[-1] - values[-2] if len(values) > 1 else 0
        )  # Last change
        features.append(values[-1] - np.mean(values))  # Deviation from mean

        # Trend features
        if len(values) >= 3:
            # Simple linear trend
            x = np.arange(len(values))
            slope = np.polyfit(x, values, 1)[0]
            features.append(slope)
        else:
            features.append(0)

        # Sensor-specific features (hash of sensor_id for uniqueness)
        sensor_hash = hash(data[-1]["sensor"]) if data else 0
        features.append((sensor_hash % 1000) / 1000.0)  # Normalize hash

        # Time features for prediction time
        features.append(pred_time.hour)
        features.append(pred_time.weekday())
        features.append(pred_time.minute / 60.0)

        # Minutes ahead (normalized by max default horizon: 1440 minutes = 24 hours)
        features.append(minutes_ahead / 1440.0)

        return features

    async def _get_recent_data(self, hours: int = 24) -> List[Dict]:
        """Get recent data for this sensor"""
        return await self._get_data(hours=hours)

    async def _get_data(self, hours: int = 24) -> List[Dict]:
        """Get data from database for this sensor"""
        end_time = datetime.now(timezone.utc)
        start_time = end_time - timedelta(hours=hours)

        return await Database.get_metrics_history(
            sensor=self.sensor_id,
            from_time=start_time.isoformat(),
            to_time=end_time.isoformat(),
            target_points=min(200, hours * 4),
        )

    def _calculate_confidence(self, data: List[Dict], prediction: float) -> float:
        """Calculate prediction confidence"""
        if len(data) < 3:
            return 0.5

        values = [d["value"] for d in data[-8:]]  # Recent values
        std_dev = np.std(values)
        mean_val = np.mean(values)

        # Check if prediction is reasonable
        min_val, max_val = min(values), max(values)
        data_range = max_val - min_val

        # If prediction is within 2x the recent range, high confidence
        if min_val - data_range <= prediction <= max_val + data_range:
            cv = std_dev / mean_val if mean_val != 0 else 1
            confidence = max(0.3, min(0.9, 1 - cv))
        else:
            confidence = 0.2  # Low confidence for outlier predictions

        return round(confidence, 2)


# Global dictionary to store models per sensor
sensor_models: Dict[str, SensorModel] = {}


def get_sensor_model(sensor_id: str) -> SensorModel:
    """Get or create model for sensor"""
    if sensor_id not in sensor_models:
        sensor_models[sensor_id] = SensorModel(sensor_id)
    return sensor_models[sensor_id]


async def predict_sensor(sensor_id: str, horizons: List[int] = None) -> Dict:
    """Main prediction function - gets model from dictionary"""
    model = get_sensor_model(sensor_id)
    return await model.predict(horizons or [15, 60, 360, 1440])


def clear_all_models():
    """Clear all loaded models to force retraining with new features"""
    global sensor_models
    logger.info(f"Clearing {len(sensor_models)} loaded models")
    sensor_models.clear()


def clear_sensor_model(sensor_id: str):
    """Clear a specific sensor model to force retraining"""
    if sensor_id in sensor_models:
        logger.info(f"Clearing model for sensor {sensor_id}")
        del sensor_models[sensor_id]
