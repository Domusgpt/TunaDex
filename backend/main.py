import os
import json
from datetime import datetime, timedelta, date # Added date
from typing import Dict, List, Optional, Any
from fastapi import FastAPI, File, UploadFile, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse, FileResponse
import uvicorn
import logging # Added for better logging

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = FastAPI(title="Seafood Shipment API")

# Add CORS middleware - Allow all for development simplicity
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],  # Allows all methods
    allow_headers=["*"],  # Allows all headers
)

# Define base directory (adjustable for Termux environment)
# Assumes main.py is in TunaDex0.2/backend/
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(BASE_DIR)
DATA_DIR = os.path.join(PARENT_DIR, "data")
DAILY_DIR = os.path.join(DATA_DIR, "daily")
FRONTEND_DIR = os.path.join(PARENT_DIR, "frontend")

logger.info(f"Base Directory: {BASE_DIR}")
logger.info(f"Parent Directory: {PARENT_DIR}")
logger.info(f"Data Directory: {DATA_DIR}")
logger.info(f"Daily Data Directory: {DAILY_DIR}")
logger.info(f"Frontend Directory: {FRONTEND_DIR}")


# Ensure data directories exist
for directory in [DATA_DIR, DAILY_DIR]:
    if not os.path.exists(directory):
        os.makedirs(directory)
        logger.info(f"Created directory: {directory}")

# API endpoints
@app.post("/api/upload/daily")
async def upload_daily_data(file: UploadFile = File(...)):
    """Upload daily shipment data file."""
    # Use lower() for case-insensitive check
    if not file.filename.lower().endswith(".json"):
        logger.warning(f"Upload rejected: File '{file.filename}' is not JSON.")
        raise HTTPException(status_code=400, detail="File must be a JSON document (.json)")

    try:
        # Read and validate data
        content = await file.read()
        data = json.loads(content)
        logger.info(f"Received file '{file.filename}' for upload.")

        # Basic validation
        required_fields = ["date", "supplier", "shipments", "totals"]
        for field in required_fields:
            if field not in data:
                logger.error(f"Upload failed: Missing '{field}' field in JSON data from '{file.filename}'.")
                raise HTTPException(
                    status_code=400,
                    detail=f"Invalid data format. Missing '{field}' field"
                )

        # Generate filename from data
        date_str = data.get("date", datetime.now().strftime("%Y-%m-%d"))
        supplier = data.get("supplier", "unknown").lower().strip().replace(" ", "_") # Sanitize supplier name
        if not supplier: supplier = "unknown"

        # Validate internal date format
        try:
            datetime.strptime(date_str, "%Y-%m-%d")
        except ValueError:
             logger.error(f"Upload failed: Invalid date format '{date_str}' in '{file.filename}'. Expected YYYY-MM-DD.")
             raise HTTPException(status_code=400, detail="Invalid date format in JSON. Expected YYYY-MM-DD.")

        filename = f"{date_str}_{supplier}.json"
        file_path = os.path.join(DAILY_DIR, filename)

        # Save file (overwrite if exists)
        with open(file_path, "wb") as f:
            f.write(content)
        logger.info(f"File saved successfully to '{file_path}'.")

        return {"message": "File uploaded successfully", "file_path": file_path}

    except json.JSONDecodeError:
        logger.error(f"Upload failed: Invalid JSON format in '{file.filename}'.")
        raise HTTPException(status_code=400, detail="Invalid JSON format")
    except HTTPException as http_exc:
        # Re-raise HTTP exceptions
        raise http_exc
    except Exception as e:
        logger.exception(f"An unexpected error occurred during file upload: {e}")
        raise HTTPException(status_code=500, detail=f"An unexpected error occurred: {str(e)}")

# Helper function to get report data
def get_report_data_from_files(start_date_str: str, end_date_str: str) -> Dict[str, List[Any]]:
    """Loads and aggregates data from JSON files within the date range."""
    report_data = {
        "dailyData": [],
        "speciesData": [],
        "customerData": [],
        "swordData": []
    }
    processed_files = []

    try:
        start = datetime.strptime(start_date_str, "%Y-%m-%d").date()
        end = datetime.strptime(end_date_str, "%Y-%m-%d").date()
    except ValueError:
        logger.error(f"Invalid date format provided. Start: '{start_date_str}', End: '{end_date_str}'")
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    if start > end:
        logger.warning(f"Query rejected: Start date '{start_date_str}' is after end date '{end_date_str}'.")
        raise HTTPException(status_code=400, detail="Start date must be before or equal to end date")

    logger.info(f"Fetching report data from {start_date_str} to {end_date_str}")

    # Find JSON files in the data directory
    if not os.path.exists(DAILY_DIR):
         logger.warning(f"Daily data directory not found: {DAILY_DIR}")
         return report_data # Return empty data

    for filename in os.listdir(DAILY_DIR):
        # Expecting filenames like YYYY-MM-DD_supplier.json
        if filename.lower().endswith('.json'): # Case-insensitive check
            try:
                # Extract date from filename robustly
                # Handle cases like 'YYYY-MM-DD.json' or 'YYYY-MM-DD_supplier.json'
                parts = filename.split('_')
                file_date_str = parts[0]
                # More robust date check at start of filename
                if len(file_date_str) == 10 and file_date_str[4] == '-' and file_date_str[7] == '-':
                     file_date = datetime.strptime(file_date_str, "%Y-%m-%d").date()
                else:
                    # Attempt to parse just the end part if it looks like date.json
                    if len(filename) >= 15 and filename.lower().endswith('.json'): # YYYY-MM-DD.json = 15 chars
                        potential_date = filename[:-5] # remove .json
                        if len(potential_date) == 10 and potential_date[4] == '-' and potential_date[7] == '-':
                           file_date = datetime.strptime(potential_date, "%Y-%m-%d").date()
                        else:
                             logger.warning(f"Skipping file '{filename}': Cannot determine date part reliably.")
                             continue
                    else:
                         logger.warning(f"Skipping file '{filename}': Cannot determine date part reliably.")
                         continue


                # Check if file is within date range
                if start <= file_date <= end:
                    file_path = os.path.join(DAILY_DIR, filename)
                    processed_files.append(filename)
                    logger.debug(f"Processing file: {filename}")

                    with open(file_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)

                    # Basic validation of loaded data
                    if not all(k in data for k in ["date", "totals", "shipments"]):
                         logger.warning(f"Skipping file '{filename}': Missing required keys (date, totals, shipments).")
                         continue
                    if not isinstance(data["totals"], dict) or not all(k in data["totals"] for k in ["total_boxes", "total_weight_lbs", "customer_breakdown", "species_breakdown"]):
                         logger.warning(f"Skipping file '{filename}': Invalid 'totals' structure.")
                         continue


                    # Process daily data summary
                    day_data = {
                        "date": data["date"], # Use date from file content
                        "boxes": data["totals"].get("total_boxes", 0),
                        "weight": data["totals"].get("total_weight_lbs", 0.0),
                        "customers": len(data["totals"].get("customer_breakdown", {})),
                        "species": data["totals"].get("species_breakdown", {}),
                        "shipments": data.get("shipments", []) # Include shipments for detail view
                    }
                    report_data["dailyData"].append(day_data)

            except ValueError:
                logger.warning(f"Skipping file '{filename}': Could not parse date from filename or content.")
            except json.JSONDecodeError:
                logger.warning(f"Skipping file '{filename}': Invalid JSON content.")
            except Exception as e:
                logger.exception(f"Error processing file '{filename}': {e}")
                continue # Skip file on unexpected error

    logger.info(f"Processed {len(processed_files)} files for the date range: {processed_files}")

    # Sort daily data by date
    report_data["dailyData"].sort(key=lambda x: x.get("date", "9999-12-31")) # Sort, handle missing date

    # Generate aggregate data only if we have daily data
    if report_data["dailyData"]:
        calculate_aggregate_data(report_data)
    else:
        logger.info("No daily data found for the specified range. Skipping aggregation.")


    return report_data

def calculate_aggregate_data(report_data: Dict[str, List[Any]]):
    """Calculates species, customer, and swordfish aggregates."""
    daily_data = report_data["dailyData"]

    # --- Aggregate Species Data ---
    species_totals = {}
    total_weight_overall = 0.0
    for day in daily_data:
        # Iterate through the species breakdown in the 'totals' section
        for species, details in day.get("species", {}).items():
            if not isinstance(details, dict): continue # Skip if structure isn't as expected
            species_name = str(species).strip() # Clean up species name
            if not species_name: continue # Skip empty names

            if species_name not in species_totals:
                species_totals[species_name] = {"boxes": 0, "value": 0.0}

            boxes = details.get("boxes", 0)
            weight = details.get("weight_lbs", 0.0)

            # Ensure numeric types
            if isinstance(boxes, (int, float)):
                species_totals[species_name]["boxes"] += boxes
            if isinstance(weight, (int, float)):
                species_totals[species_name]["value"] += weight
                total_weight_overall += weight # Accumulate for percentage calculation later

    # Convert species totals to list format for the frontend
    report_data["speciesData"] = [
        {"name": species, "value": totals["value"], "boxes": totals["boxes"]}
        for species, totals in species_totals.items() if totals["value"] > 0 # Only include species with weight > 0
    ]
    report_data["speciesData"].sort(key=lambda x: x["value"], reverse=True)
    logger.debug(f"Aggregated species data: {report_data['speciesData']}")


    # --- Aggregate Customer Data ---
    customer_totals = {}
    for day in daily_data:
        for shipment in day.get("shipments", []):
             if not isinstance(shipment, dict): continue # Skip invalid shipment entries
             # Use .get() with defaults for safety
             company = str(shipment.get("company", "Unknown")).strip()
             if not company: company = "Unknown" # Handle empty company names

             boxes = shipment.get("boxes", 0)
             weight = shipment.get("weight_lbs", 0.0)

             if company not in customer_totals:
                 customer_totals[company] = {"boxes": 0, "value": 0.0}

             # Ensure numeric types before adding
             if isinstance(boxes, (int, float)):
                 customer_totals[company]["boxes"] += boxes
             if isinstance(weight, (int, float)):
                 customer_totals[company]["value"] += weight

    # Convert customer totals to list format
    report_data["customerData"] = [
        {"name": company, "value": totals["value"], "boxes": totals["boxes"]}
        for company, totals in customer_totals.items() if totals["value"] > 0 # Only include customers with weight > 0
    ]
    report_data["customerData"].sort(key=lambda x: x["value"], reverse=True)
    report_data["customerData"] = report_data["customerData"][:5] # Top 5 customers
    logger.debug(f"Aggregated top 5 customer data: {report_data['customerData']}")


    # --- Aggregate Swordfish Data ---
    sword_totals = {}
    for day in daily_data:
        for shipment in day.get("shipments", []):
            if not isinstance(shipment, dict): continue
            # Case-insensitive check for species
            if str(shipment.get("species", "")).strip().lower() == "swordfish":
                company = str(shipment.get("company", "Unknown")).strip()
                if not company: company = "Unknown"

                boxes = shipment.get("boxes", 0)
                weight = shipment.get("weight_lbs", 0.0)

                # Only process if weight and boxes are valid numbers
                if isinstance(boxes, (int, float)) and isinstance(weight, (int, float)):
                    if company not in sword_totals:
                        sword_totals[company] = {"boxes": 0.0, "weight": 0.0} # Use float for potential fractional boxes? No, stick to int for boxes typically. Use float for weight.

                    sword_totals[company]["boxes"] += boxes
                    sword_totals[company]["weight"] += weight
                else:
                    logger.warning(f"Invalid numeric type for boxes/weight in swordfish shipment for '{company}' on {day.get('date')}. Skipping.")


    # Convert swordfish totals to list format
    report_data["swordData"] = [] # Initialize as empty list
    for company, totals in sword_totals.items():
        # Only include if there are boxes and weight to calculate average
        if totals["boxes"] > 0 and totals["weight"] > 0:
            avg_size = totals["weight"] / totals["boxes"]
            # Use first word of company name, handle potential index errors
            company_name_parts = company.split(" ")
            display_name = company_name_parts[0] if company_name_parts else "Unknown"

            report_data["swordData"].append({
                "name": display_name,
                "avgSize": avg_size,
                "boxes": totals["boxes"]
            })
        elif totals["boxes"] > 0: # If boxes exist but no weight, maybe still include? Or log warning?
             logger.warning(f"Swordfish entry for '{company}' has {totals['boxes']} boxes but 0 weight. Excluding from avgSize calculation.")


    report_data["swordData"].sort(key=lambda x: x["avgSize"], reverse=True)
    logger.debug(f"Aggregated swordfish data: {report_data['swordData']}")


# --- API Endpoints for Reports ---

# Base endpoint for reports, reducing redundancy
async def get_report(
    start_date: str = Query(..., description="Start date in YYYY-MM-DD format"),
    end_date: str = Query(..., description="End date in YYYY-MM-DD format"),
    report_type: str = "daily" # Added to know which endpoint was called
):
    """Generate shipment report for a date range."""
    logger.info(f"Received request for {report_type} report: {start_date} to {end_date}")
    try:
        report_data = get_report_data_from_files(start_date, end_date)
        # Placeholder for future weekly/monthly specific aggregation logic
        if report_type == "weekly":
            # TODO: Add weekly aggregation logic here if needed
            logger.info("Processing as weekly report (using daily aggregation for now).")
            pass
        elif report_type == "monthly":
            # TODO: Add monthly aggregation logic here if needed
            logger.info("Processing as monthly report (using daily aggregation for now).")
            pass
        return report_data
    except HTTPException as http_exc:
         raise http_exc # Propagate HTTP exceptions (like 400 Bad Request)
    except Exception as e:
        logger.exception(f"Error generating {report_type} report: {e}")
        raise HTTPException(status_code=500, detail=f"Internal server error generating report: {str(e)}")


@app.get("/api/reports/daily")
async def get_daily_report_endpoint(
    start_date: str = Query(..., description="Start date in YYYY-MM-DD format"),
    end_date: str = Query(..., description="End date in YYYY-MM-DD format")
):
     return await get_report(start_date, end_date, report_type="daily")

@app.get("/api/reports/weekly")
async def get_weekly_report_endpoint(
    start_date: str = Query(..., description="Start date in YYYY-MM-DD format"),
    end_date: str = Query(..., description="End date in YYYY-MM-DD format")
):
    return await get_report(start_date, end_date, report_type="weekly")

@app.get("/api/reports/monthly")
async def get_monthly_report_endpoint(
    start_date: str = Query(..., description="Start date in YYYY-MM-DD format"),
    end_date: str = Query(..., description="End date in YYYY-MM-DD format")
):
    return await get_report(start_date, end_date, report_type="monthly")


# --- Static File Serving ---

# Check if FRONTEND_DIR exists before mounting
if os.path.isdir(FRONTEND_DIR):
    # Check if index.html exists within frontend dir
    index_path_check = os.path.join(FRONTEND_DIR, "index.html")
    if not os.path.isfile(index_path_check):
        logger.error(f"index.html not found in frontend directory: {FRONTEND_DIR}")
        # Define a handler for root path if index.html is missing
        @app.get("/")
        async def root_no_index():
            return JSONResponse(
                status_code=404,
                content={"message": "Backend running, but index.html is missing from the frontend directory."}
                )
    else:
        logger.info(f"Mounting static files from: {FRONTEND_DIR}")
        # Mount static files, html=True enables serving index.html at root
        app.mount("/", StaticFiles(directory=FRONTEND_DIR, html=True), name="frontend")

        # This explicit root handler might not be strictly necessary when html=True,
        # but can act as a fallback or override. It's generally safe to keep.
        @app.get("/")
        async def get_index():
            index_path = os.path.join(FRONTEND_DIR, "index.html")
            return FileResponse(index_path)

else:
     logger.error(f"Frontend directory '{FRONTEND_DIR}' not found. Static files will not be served.")
     # Add a root handler to inform the user if the frontend is missing
     @app.get("/")
     async def root_fallback_no_frontend():
         return JSONResponse(
             status_code=404,
             content={"message": "Backend is running, but the frontend directory was not found."}
         )


# --- Main Execution ---
if __name__ == "__main__":
    logger.info("Starting Uvicorn server...")
    # Bind to 0.0.0.0 to make it accessible on the network (important for mobile access)
    # Use reload=True only for development (listens for code changes)
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)

