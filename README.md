# Seafood Shipment Dashboard (TunaDex0.2)

A mobile-friendly dashboard for tracking seafood shipments using FastAPI and Chart.js.

## Features

1.  Upload daily shipment JSON files.
2.  Visualize shipment data with charts and tables for a selected date range.
3.  View daily summaries, species distribution, top customers, and swordfish average sizes.
4.  Basic responsive design for mobile/desktop.

## Getting Started (Termux)

1.  **Navigate to Project Directory:**
    ```bash
    cd /storage/emulated/0/TunaDex0.2
    ```

2.  **Ensure Dependencies are Installed:**
    If you haven't already installed them via the setup script:
    ```bash
    pip install fastapi uvicorn[standard] python-multipart
    ```

3.  **Start the Backend Server:**
    Make sure the script is executable (`chmod +x run_backend.sh` if needed).
    ```bash
    ./run_backend.sh
    ```
    The server will run on `http://localhost:8000` and `http://<your_device_ip>:8000`.

4.  **Access the Dashboard:**
    Open a web browser on your device (or another device on the same network) and go to:
    *   `http://localhost:8000` (on the device running Termux)
    *   `http://<your_device_ip>:8000` (from another device, replace `<your_device_ip>` with the actual IP address of your Termux device)

## Creating JSON Data Files

*   Use the format specified in `json_template.json`.
*   You can potentially use an AI assistant like Claude to help structure data from emails/notes into this JSON format.
*   Save the generated JSON files (e.g., `YYYY-MM-DD_supplier.json`) into the `/storage/emulated/0/TunaDex0.2/data/daily/` directory.
*   Alternatively, use the "Upload File" button in the web interface.

## Directory Structure

- `/data/daily/`: Stores daily shipment JSON files (e.g., `2024-01-15_victor.json`).
- `/backend/`: Contains the FastAPI Python backend code (`main.py`).
- `/frontend/`: Contains the HTML, CSS, and JavaScript for the dashboard (`index.html`, `js/chart.min.js`).
- `run_backend.sh`: Script to easily start the server.
- `json_template.json`: Template showing the expected JSON data format.
- `README.md`: This file.

## JSON Schema

See `json_template.json` for the detailed structure expected for the daily data files. Key fields include `date`, `supplier`, `shipments` (list of individual shipments), and `totals` (summary).
