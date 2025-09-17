import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from dotenv import load_dotenv
import uvicorn

from config import setup_logging
from database import Database
from routes import router

load_dotenv()
logger = setup_logging()


class AuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.auth_token = os.getenv("AUTH_TOKEN")

    async def dispatch(self, request: Request, call_next):
        auth_header = request.headers.get("protected")

        if auth_header != self.auth_token:
            return JSONResponse(status_code=401, content={})

        response = await call_next(request)
        return response


@asynccontextmanager
async def lifespan(_: FastAPI):
    try:
        database_url = os.getenv("DATABASE_URL")
        Database.initialize(database_url)
        logger.info("Database initialized")

        await Database.wait_for_connection()
        logger.info("Database connected")

        await Database.create_tables()
        logger.info("Tables created")

        logger.info("Application started")
    except Exception as e:
        logger.error(f"Startup failed: {e}")
        raise

    yield

    await Database.cleanup()
    logger.info("Application shutdown")


app = FastAPI(title="Server", version="0.1.0", lifespan=lifespan)
app.add_middleware(AuthMiddleware)
app.include_router(router)


def main():
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    debug = os.getenv("DEBUG", "true").lower() == "true"

    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        reload=debug,
        log_level="info" if not debug else "debug",
    )


if __name__ == "__main__":
    main()
