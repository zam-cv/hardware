# Multi-stage build for optimized production image  
FROM python:3.12-slim AS builder

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Set working directory
WORKDIR /app

# Enable bytecode compilation and copy mode for Docker
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies with cache mount
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

# Copy application code
COPY . .

# Install the project with cache mount
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# Production stage
FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install curl, Tailscale, and system dependencies for ML libraries
RUN apt-get update && apt-get install -y \
    curl \
    file \
    net-tools \
    ca-certificates \
    iptables \
    libgomp1 \
    libgcc-s1 \
    && curl -fsSL https://tailscale.com/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Create user home directory and cache directories
RUN mkdir -p /home/appuser/.cache/uv && \
    chown -R appuser:appuser /home/appuser

# Create Tailscale directories and set ownership
RUN mkdir -p /var/lib/tailscale /var/run/tailscale && \
    chown -R appuser:appuser /var/lib/tailscale /var/run/tailscale

# Set working directory
WORKDIR /app

# Copy the virtual environment and application from builder
COPY --from=builder --chown=appuser:appuser /app /app

# Copy startup script
COPY <<EOF ./start.sh
#!/bin/sh
set -e

# Check if TS_AUTHKEY is provided
if [ -z "\$TS_AUTHKEY" ]; then
    echo "Error: TS_AUTHKEY environment variable is required"
    exit 1
fi

# Start tailscaled in userspace mode (no privileges needed)
echo "Starting Tailscale in userspace mode..."
tailscaled --state=\$TS_STATE_DIR/tailscaled.state --tun=userspace-networking &
TAILSCALED_PID=\$!

# Wait for tailscaled to start
sleep 5

# Authenticate with Tailscale
echo "Connecting to Tailscale network..."
tailscale up --authkey=\$TS_AUTHKEY --hostname=hardware-server

# Enable funnel in background
echo "Enabling Tailscale Funnel on port 8000..."
tailscale funnel --bg 8000

# Start the Python application as the main process
echo "Starting Python server..."
export PYTHONPATH="/app/.venv/lib/python3.12/site-packages:\$PYTHONPATH"
exec python src/main.py
EOF

# Make startup script executable and fix ownership
RUN chmod +x ./start.sh && chown appuser:appuser ./start.sh

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TS_STATE_DIR=/var/lib/tailscale

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 8000

# Run the application
CMD ["./start.sh"]