#!/bin/bash

# Navigate to the directory containing this script (TunaDex0.2)
cd "$(dirname "$0")" || exit 1

# Navigate to the backend directory
cd backend || exit 1

# Check if uvicorn is installed (optional but helpful)
if ! command -v uvicorn &> /dev/null
then
    echo "uvicorn could not be found. Please install it: pip install uvicorn[standard]"
    exit 1
fi

echo "Starting FastAPI backend server on http://0.0.0.0:8000"
echo "Access via http://localhost:8000 or http://<your-device-ip>:8000"
echo "Press Ctrl+C to stop the server."

# Run uvicorn, binding to 0.0.0.0 makes it accessible over the network
# Use --reload for development, remove it for production
uvicorn main:app --host 0.0.0.0 --port 8000 --reload

echo "Backend server stopped."
