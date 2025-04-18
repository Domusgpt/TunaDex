#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
SOURCE_DIR="/storage/emulated/0/TunaDex0.2"
TARGET_DIR="/storage/emulated/0/TunaDex0.3"
# Use the exact name of the deployment script located INSIDE the SOURCE_DIR
DEPLOY_SCRIPT_NAME="deploy_tunadex_azure.sh" # Make sure this filename is correct!

echo ">>> Preparing to copy project to new location <<<"
echo ">>> Source: ${SOURCE_DIR}"
echo ">>> Target: ${TARGET_DIR}"
echo ">>> WARNING: Target directory '${TARGET_DIR}' will be DELETED if it exists!"
sleep 4 # Give user time to read the warning

# --- Pre-checks ---
echo ">>> Checking source directory..."
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "ERROR: Source directory '${SOURCE_DIR}' not found! Cannot copy."
    exit 1
fi

echo ">>> Checking for deployment script in source..."
if [ ! -f "${SOURCE_DIR}/${DEPLOY_SCRIPT_NAME}" ]; then
    echo "ERROR: Deployment script '${DEPLOY_SCRIPT_NAME}' not found inside '${SOURCE_DIR}'!"
    echo "Make sure the deployment script is saved inside ${SOURCE_DIR}."
    exit 1
fi

BASE_STORAGE_DIR=$(dirname "${TARGET_DIR}")
if [ ! -d "${BASE_STORAGE_DIR}" ]; then
    echo "ERROR: Base storage directory '${BASE_STORAGE_DIR}' not accessible."
    echo "Ensure Termux storage access is working."
    exit 1
fi

# --- Copy Operation ---
echo ">>> Copying project files..."
# Remove existing target for a clean copy
if [ -d "${TARGET_DIR}" ]; then
    echo ">>> Removing existing target directory: ${TARGET_DIR}"
    rm -rf "${TARGET_DIR}" || { echo "Failed to remove target directory."; exit 1; }
fi

# Copy using rsync, exclude .git to avoid carrying over old git state
# The deploy script will handle git init for the new directory
echo ">>> Copying from ${SOURCE_DIR}/ to ${TARGET_DIR}/ (excluding .git)..."
rsync -a --exclude '.git' --exclude 'venv/' --exclude 'tunadex_app_venv/' "${SOURCE_DIR}/" "${TARGET_DIR}/" || { echo "Project file copy failed."; exit 1; }
echo ">>> Project copy complete."

# --- Run Deployment from New Location ---
echo ">>> Navigating to new directory: ${TARGET_DIR}"
cd "${TARGET_DIR}" || { echo "Failed to cd into target directory"; exit 1; }
echo ">>> Current directory: $(pwd)"

echo ">>> Making deployment script executable in new location..."
chmod +x "${DEPLOY_SCRIPT_NAME}" || { echo "Failed to make script executable."; exit 1; }

echo ">>> Executing deployment script (${DEPLOY_SCRIPT_NAME}) from ${TARGET_DIR}..."
echo ">>> Follow prompts for GitHub PAT and Azure Login carefully!"
sleep 3

./"${DEPLOY_SCRIPT_NAME}" # Execute the copied deployment script

echo ">>> Main copy script finished. Azure deployment script is running/has run."
echo ">>> Working inside: ${TARGET_DIR}"