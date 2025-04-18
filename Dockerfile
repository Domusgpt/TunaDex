# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Install system dependencies needed for compilation (Rust, C tools)
# Combine RUN commands to reduce layers
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        pkg-config \
        rustc \
        cargo && \
    # Clean up apt cache to reduce image size
    rm -rf /var/lib/apt/lists/*

# Copy the requirements file into the container
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
# Use --no-cache-dir to keep the image smaller
# This is where the slow compilation happens ONCE during the build
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
# Adjust if your structure is different (e.g., copy specific folders)
COPY ./backend ./backend
COPY ./frontend ./frontend
# Optionally copy data if you want it baked into the image,
# otherwise use volumes when running the container.
# COPY ./data ./data

# Make port 8000 available to the world outside this container
EXPOSE 8000

# Define environment variables if needed
# ENV NAME World

# Run uvicorn server when the container launches
# Use 0.0.0.0 to accept connections from outside the container
# Do NOT use --reload in the default CMD for a production-like image
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]

