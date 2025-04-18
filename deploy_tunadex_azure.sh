#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
echo ">>> STEP 0: CONFIGURATION <<<"
PROJECT_DIR="/storage/emulated/0/TunaDex0.2"
GITHUB_USER="Domusgpt"
GITHUB_EMAIL="phillips.paul.email@gmail.com" # Your Email
GITHUB_REPO_URL="https://github.com/Domusgpt/TunaDex.git"
GITHUB_BRANCH_LOCAL="master"  # Your local branch name
GITHUB_BRANCH_REMOTE="main"   # Target branch name on GitHub

# --- Azure Configuration ---
AZ_RESOURCE_GROUP="TunaDexResourceGroup"
AZ_LOCATION="brazilsouth"
AZ_STORAGE_ACCOUNT="tunadexstoragex"
AZ_FILE_SHARE="tunadata"
AZ_APP_PLAN="TunaDexAppPlan"
AZ_WEB_APP="tunadex-app"   # Your chosen Web App Name (MUST BE GLOBALLY UNIQUE)

# --- Verify Placeholders Replaced (Check Email specifically) ---
if [[ "$GITHUB_EMAIL" == "<Your_GitHub_Registered_Email@example.com>" ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "ERROR: You MUST replace the GITHUB_EMAIL placeholder!!!"
  echo "Edit the script variable near the top before running."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  exit 1
fi
# Basic check for Azure placeholders (less critical as they were confirmed)
if [[ "$AZ_RESOURCE_GROUP" == "<YourResourceGroupName>" || "$AZ_LOCATION" == "<YourAzureLocation>" || "$AZ_STORAGE_ACCOUNT" == "<YourStorageAccountName>" || "$AZ_FILE_SHARE" == "<YourFileShareName>" || "$AZ_APP_PLAN" == "<YourAppServicePlanName>" || "$AZ_WEB_APP" == "<YourWebAppName>" ]]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "ERROR: One or more Azure placeholders (<...>) still exist. Please verify Azure variables."
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  exit 1
fi


# --- START EXECUTION ---
echo ">>> Starting Full Setup & Azure Deployment <<<"
echo ">>> Project Directory: ${PROJECT_DIR}"
echo ">>> GitHub User: ${GITHUB_USER}"
echo ">>> GitHub Email: ${GITHUB_EMAIL}"
echo ">>> Azure Resource Group: ${AZ_RESOURCE_GROUP}"
echo ">>> Azure Location: ${AZ_LOCATION}"
echo ">>> Azure Storage Account: ${AZ_STORAGE_ACCOUNT}"
echo ">>> Azure File Share: ${AZ_FILE_SHARE}"
echo ">>> Azure App Plan: ${AZ_APP_PLAN}"
echo ">>> Azure Web App: ${AZ_WEB_APP}"
echo ">>> NOTE: If Azure Web App name '${AZ_WEB_APP}' is taken, the script will fail later."
sleep 5

# --- Termux Base Setup ---
echo ">>> STEP 1: Updating Termux packages..."
pkg update && pkg upgrade -y || { echo "Termux update failed"; exit 1; }

echo ">>> STEP 2: Installing Termux prerequisites: git, proot-distro..."
pkg install git proot-distro wget curl -y || { echo "Termux prerequisite install failed"; exit 1; }

# --- Ensure Project Directory Exists ---
if [ ! -d "${PROJECT_DIR}" ]; then
  echo "ERROR: Project directory ${PROJECT_DIR} not found. Exiting."
  exit 1
fi
cd "${PROJECT_DIR}" || { echo "Failed to cd into project directory"; exit 1; }
echo ">>> Changed directory to ${PROJECT_DIR}"

# --- Proot Distro Ubuntu Setup ---
echo ">>> STEP 3: Installing/Updating Ubuntu via proot-distro (Will take time)..."
proot-distro install ubuntu || echo "Ubuntu already installed or install failed, continuing..."

echo ">>> STEP 4: Installing dependencies inside Ubuntu (Will take time)..."
# Run multiple commands inside Ubuntu using bash -c
# Use DEBIAN_FRONTEND=noninteractive to avoid interactive prompts
proot-distro login ubuntu -- bash -c '
  set -e # Exit script if any command fails inside here
  export DEBIAN_FRONTEND=noninteractive
  echo ">>> [Ubuntu] Updating package lists..."
  apt-get update -y && apt-get upgrade -y
  echo ">>> [Ubuntu] Installing build tools, Python, Rust, curl..."
  apt-get install -y --no-install-recommends \
    build-essential clang pkg-config \
    rustc cargo \
    python3 python3-pip python3-venv \
    curl ca-certificates gnupg lsb-release git wget
  echo ">>> [Ubuntu] Cleaning apt cache..."
  rm -rf /var/lib/apt/lists/*
  # echo ">>> [Ubuntu] Upgrading pip..." # <<<--- COMMENTED OUT
  # python3 -m pip install --upgrade pip && \ # <<<--- COMMENTED OUT
  echo ">>> [Ubuntu] Installing Azure CLI..."
  wget -O az_installer.sh https://aka.ms/InstallAzureCLIDeb
  bash az_installer.sh || { echo "Azure CLI install failed"; exit 1; }
  rm az_installer.sh
  echo ">>> [Ubuntu] Dependency installation finished." || \
  { echo ">>> [Ubuntu] ERROR: Failed to install dependencies inside Ubuntu."; exit 1; }
'
# Check if the above command block succeeded by checking exit code
if [ $? -ne 0 ]; then echo "ERROR: Proot Ubuntu dependency installation failed."; exit 1; fi
echo ">>> Ubuntu setup complete."
sleep 2

# --- Git Setup & Push ---
echo ">>> STEP 5: Configuring Git..."
git config --global user.name "${GITHUB_USER}" || echo "Warning: Failed to set git user.name"
git config --global user.email "${GITHUB_EMAIL}" || echo "Warning: Failed to set git user.email"
git config --global --add safe.directory "${PROJECT_DIR}" || echo "Warning: Failed to set safe.directory"

echo ">>> STEP 6: Ensuring project files exist..."
# Ensure Dockerfile exists
if [ ! -f Dockerfile ]; then
  echo ">>> Creating Dockerfile..."
  cat << EOF > Dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential clang pkg-config rustc cargo && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && pip install --no-cache-dir -r requirements.txt
COPY ./backend ./backend
COPY ./frontend ./frontend
RUN mkdir /app/data
EXPOSE 8000
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
fi
# Ensure requirements.txt exists
if [ ! -f requirements.txt ]; then
  echo ">>> Creating requirements.txt..."
  echo "fastapi" > requirements.txt
  echo "uvicorn[standard]" >> requirements.txt
  echo "python-multipart" >> requirements.txt
fi
# Ensure .gitignore exists
if [ ! -f .gitignore ]; then
  echo ">>> Creating .gitignore..."
  curl -L -o .gitignore https://raw.githubusercontent.com/github/gitignore/main/Python.gitignore || echo "Warning: Failed to download .gitignore template."
  echo -e "\n# Custom\n.venv/\nvenv/\ntunadex_app_venv/\n__pycache__/\n*.pyc" >> .gitignore
fi

# Initialize Git repo if needed
if [ ! -d .git ]; then
  echo ">>> Initializing Git repository..."
  git init
  # Set default branch name if initializing (modern practice)
  # Note: git config init.defaultBranch requires newer Git; try simpler branch rename later if needed
  # git config --local init.defaultBranch main
  git checkout -b ${GITHUB_BRANCH_REMOTE} || git checkout ${GITHUB_BRANCH_REMOTE} # Try to create/switch to 'main' (or target remote name)
  GITHUB_BRANCH_LOCAL="${GITHUB_BRANCH_REMOTE}" # Assume local should match remote now
fi

# Add/Verify remote
if ! git remote get-url origin > /dev/null 2>&1; then
  echo ">>> Adding GitHub remote 'origin'..."
  git remote add origin "${GITHUB_REPO_URL}"
else
  echo ">>> Verifying GitHub remote 'origin' URL..."
  git remote set-url origin "${GITHUB_REPO_URL}"
fi

echo ">>> STEP 7: Staging and Committing all changes..."
git add . || { echo "git add failed"; exit 1; }
# Only commit if there are changes staged
if ! git diff --staged --quiet; then
  # Get current date/time for commit message
  COMMIT_MSG="Automated setup: Prepare for Azure deployment $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Committing with message: ${COMMIT_MSG}"
  git commit -m "${COMMIT_MSG}"
else
  echo ">>> No changes detected to commit."
fi

echo ">>> STEP 8: Pushing code to GitHub ( ${GITHUB_BRANCH_LOCAL} -> ${GITHUB_BRANCH_REMOTE} )..."
echo ">>> IMPORTANT: You will be prompted for GitHub username and PAT (Personal Access Token) as password."
sleep 5
# Force push to handle potential branch name differences or previous failed attempts
git push --force -u origin "${GITHUB_BRANCH_LOCAL}:${GITHUB_BRANCH_REMOTE}"
if [ $? -ne 0 ]; then echo "ERROR: Git push failed. Check credentials (use PAT for password) and repository state."; exit 1; fi
echo ">>> Code push to GitHub complete."
sleep 2

# --- Azure Deployment ---
echo ">>> STEP 9: Initiating Azure Deployment (Will take time)..."
# Run Azure commands inside Ubuntu session
proot-distro login ubuntu -- bash -c '
  set -e # Exit if any command fails inside here

  # --- Define Variables Again INSIDE Ubuntu ---
  # Quote variables passed from outside to handle potential special characters
  RESOURCE_GROUP="'"${AZ_RESOURCE_GROUP}"'"
  LOCATION="'"${AZ_LOCATION}"'"
  STORAGE_ACCOUNT="'"${AZ_STORAGE_ACCOUNT}"'"
  FILE_SHARE="'"${AZ_FILE_SHARE}"'"
  APP_PLAN="'"${AZ_APP_PLAN}"'"
  WEB_APP="'"${AZ_WEB_APP}"'"
  GITHUB_REPO="'"${GITHUB_REPO_URL}"'"
  GITHUB_BRANCH="'"${GITHUB_BRANCH_REMOTE}"'" # Use the target remote branch name

  echo ">>> [Azure] Logging into Azure..."
  echo ">>> IMPORTANT: Follow the device code instructions in your browser."
  az login || { echo "[Azure] ERROR: az login failed."; exit 1; }
  echo ">>> [Azure] Login successful."

  # --- Optional: Set subscription if needed ---
  # AZ_SUBSCRIPTION_ID="<YourSubscriptionIdIfDifferent>"
  # if [ -n "${AZ_SUBSCRIPTION_ID}" ]; then
  #    echo ">>> [Azure] Setting subscription..."
  #    az account set --subscription "${AZ_SUBSCRIPTION_ID}" || { echo "[Azure] ERROR: Failed to set subscription."; exit 1; }
  # fi

  echo ">>> [Azure] Creating Resource Group: ${RESOURCE_GROUP} in ${LOCATION}..."
  az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --output none

  echo ">>> [Azure] Creating Storage Account: ${STORAGE_ACCOUNT}..."
  az storage account create --name ${STORAGE_ACCOUNT} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard_LRS --kind StorageV2 --output none

  echo ">>> [Azure] Retrieving Storage Account Key..."
  STORAGE_KEY=$(az storage account keys list --resource-group ${RESOURCE_GROUP} --account-name ${STORAGE_ACCOUNT} --query "[0].value" -o tsv)
  if [ -z "${STORAGE_KEY}" ]; then echo "[Azure] ERROR: Failed to retrieve storage key."; exit 1; fi
  echo ">>> [Azure] Storage Key retrieved."

  echo ">>> [Azure] Creating File Share: ${FILE_SHARE}..."
  az storage share create --name ${FILE_SHARE} --account-name ${STORAGE_ACCOUNT} --account-key "${STORAGE_KEY}" --quota 5 --output none

  echo ">>> [Azure] Creating App Service Plan: ${APP_PLAN}..."
  az appservice plan create --name ${APP_PLAN} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --is-linux --sku F1 --output none

  echo ">>> [Azure] Creating Web App: ${WEB_APP} with GitHub deployment..."
  # Construct the deployment image string carefully
  DEPLOYMENT_IMAGE="DOCKER|${GITHUB_REPO}#${GITHUB_BRANCH}"
  echo ">>> [Azure] Using Deployment Image: ${DEPLOYMENT_IMAGE}"
  az webapp create --name ${WEB_APP} --resource-group ${RESOURCE_GROUP} --plan ${APP_PLAN} --deployment-container-image-name "${DEPLOYMENT_IMAGE}" --docker-registry-server-user "" --docker-registry-server-password "" --output none

  echo ">>> [Azure] Configuring Storage Mount for ${WEB_APP}..."
  az webapp config storage-account add --name ${WEB_APP} --resource-group ${RESOURCE_GROUP} --custom-id "${FILE_SHARE}-mount" --share-name ${FILE_SHARE} --mount-path "/app/data" --storage-type AzureFiles --account-name ${STORAGE_ACCOUNT} --access-key "${STORAGE_KEY}" --output none

  echo ">>> [Azure] Setting WEBSITES_PORT for ${WEB_APP}..."
  az webapp config appsettings set --name ${WEB_APP} --resource-group ${RESOURCE_GROUP} --settings WEBSITES_PORT=8000 --output none

  echo ">>> [Azure] Setup commands executed successfully."
'
# Check if the Azure command block succeeded
if [ $? -ne 0 ]; then echo "ERROR: Azure deployment command block failed."; exit 1; fi

echo "--- Azure Deployment Initiated ---"
echo "Azure is now building your Docker image from GitHub and deploying the Web App."
echo "This can take several minutes (or longer) for the first build."
echo "Monitor progress in the Azure Portal: https://portal.azure.com"
echo "Find your Web App named '${AZ_WEB_APP}' in Resource Group '${AZ_RESOURCE_GROUP}'."
echo "Your app SHOULD become available at: https://${AZ_WEB_APP}.azurewebsites.net"
echo "Once live, upload your initial data files using the dashboard's upload feature."
echo ">>> Script Finished <<<"