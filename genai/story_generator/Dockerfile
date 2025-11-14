FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY src/ ./src/

# Create prompts directory
RUN mkdir -p /app/prompts

# Expose API port
EXPOSE 8001

# Run the FastAPI application
CMD ["uvicorn", "src.story_api:app", "--host", "0.0.0.0", "--port", "8001", "--reload"]

