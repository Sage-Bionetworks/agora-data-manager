#!/bin/bash
# Exit on error, treat unset variables as an error, fail if any command in a pipeline fails
set -euo pipefail

################################################################################
# SCRIPT DESCRIPTION AND REQUIREMENTS
################################################################################
# This script gets data from synapse then imports the data to an agora DB.
# This script needs to be run from an agora bastion machine, it assumes that
# the bastion is already setup with synapse, mongoimport, mongofiles and mongosh
# command line clients

################################################################################
# CONFIGURATION SECTION - Modify these values as needed
################################################################################

# Collections Configuration
# Add or remove collections as needed for your import, as collection:file pairs
# because the collection names don't match the Synapse file names
# Note: dataversion collection is handled separately and automatically included
readonly COLLECTIONS=(
    "genes:rnaseq_differential_expression.json"
    "geneslinks:network.json"
    "geneinfo:gene_info.json"
    "teaminfo:team_info.json"
    "genesproteomics:proteomics.json"
    "genesmetabolomics:metabolomics.json"
    "genesneuropathcorr:neuropath_corr.json"
    "geneexpvalidation:target_exp_validation_harmonized.json"
    "genescoredistribution:distribution_data.json"
    "genesoverallscores:overall_scores.json"
    "rnaboxdistribution:rna_distribution_data.json"
    "proteomicsboxdistribution:proteomics_distribution_data.json"
    "proteomicstmt:proteomics_tmt.json"
    "proteomicssrm:proteomics_srm.json"
    "genesbiodomains:genes_biodomains.json"
    "biodomaininfo:biodomain_info.json"
    "nominateddrugs:nominated_drugs.json"
    "nominatedtargets:nominated_targets.json"
    "uiconfig:ui_config.json"
    "druginfo:drug_info.json"
)

# Database Configuration
readonly DB_NAME="agora"  # Target database name

# GridFS collections holding the team images (the default "fs" bucket)
readonly TEAM_IMAGES_COLLECTIONS=("fs.chunks" "fs.files")

# Expected collections that will be cross-checked before import (including dataversion)
# dataversion must stay last: it is swapped in last so that it only changes once
# every other collection is serving the new release
readonly EXPECTED_COLLECTIONS=("${COLLECTIONS[@]%%:*}" "${TEAM_IMAGES_COLLECTIONS[@]}" "dataversion")

# Don't forget to add indexes in create-indexes.js

################################################################################
# PATH CONFIGURATION
################################################################################

# Setup paths and directories (needed early for sourcing utilities)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKING_DIR="${SCRIPT_DIR}"
readonly DATA_DIR="${WORKING_DIR}/data"
readonly TEAM_IMAGES_DIR="${DATA_DIR}/team_images"

# Source logging utilities first, so error() is defined for the argument checks
# below. error() isn't available until this succeeds, so the fallback uses echo.
if [ -f "${SCRIPT_DIR}/utils/logging-utils.sh" ]; then
    source "${SCRIPT_DIR}/utils/logging-utils.sh"
else
    echo "Error: utils/logging-utils.sh not found" >&2
    exit 1
fi

################################################################################
# SCRIPT ARGUMENTS AND VALIDATION
################################################################################

# Validate required arguments
if [ $# -ne 5 ]; then
    echo "Usage: $0 <BRANCH> <SYNAPSE_PASSWORD> <DB_HOST> <DB_USER> <DB_PASS>"
    echo ""
    echo "Arguments:"
    echo "  BRANCH           - Git branch name"
    echo "  SYNAPSE_PASSWORD - Synapse authentication password or PAT"
    echo "  DB_HOST          - MongoDB host address"
    echo "  DB_USER          - MongoDB username"
    echo "  DB_PASS          - MongoDB password"
    exit 1
fi

# Assign and validate arguments
BRANCH="$1"
SYNAPSE_PASSWORD="$2"
DB_HOST="$3"
DB_USER="$4"
DB_PASS="$5"

# Validate non-empty arguments
for arg_name in BRANCH SYNAPSE_PASSWORD DB_HOST DB_USER DB_PASS; do
    if [ -z "${!arg_name}" ]; then
        error "$arg_name cannot be empty"
        exit 1
    fi
done

# Security: Prevent credential variables from being exported to child processes
export -n SYNAPSE_PASSWORD DB_USER DB_PASS 2>/dev/null || true

################################################################################
# SETUP AND INITIALIZATION
################################################################################

# Create secure MongoDB connection string - credentials passed separately
# retryWrites=false: DocumentDB only supports retryable writes from engine
# 8.0.2, and mongosh enables them by default, so writes fail without it
readonly MONGO_URI="mongodb://${DB_HOST}/${DB_NAME}?authSource=admin&retryWrites=false"
readonly MONGO_USER="$DB_USER"
readonly MONGO_PASS="$DB_PASS"

# Clear original credential variables for security
unset DB_USER DB_PASS

# Source synapse utilities
if [ -f "${SCRIPT_DIR}/utils/synapse-utils.sh" ]; then
    source "${SCRIPT_DIR}/utils/synapse-utils.sh"
else
    error "utils/synapse-utils.sh not found"
    exit 1
fi

# Source database utilities
if [ -f "${SCRIPT_DIR}/utils/database-utils.sh" ]; then
    source "${SCRIPT_DIR}/utils/database-utils.sh"
else
    error "utils/database-utils.sh not found"
    exit 1
fi

################################################################################
# ERROR HANDLING AND CLEANUP
################################################################################

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script failed with exit code $exit_code"
        # Staging collections are deliberately left in place for inspection;
        # the next run drops them before importing
        warn "Any staging collections from this run were left behind and will be"
        warn "dropped at the start of the next run"
    fi
    # Add any cleanup operations here if needed
    exit $exit_code
}

# Set trap for cleanup on script exit
trap cleanup EXIT

################################################################################
# MAIN SCRIPT EXECUTION
################################################################################

log "Starting data import for branch: $BRANCH"

# Start timing
SCRIPT_START_TIME=$(date +%s)

################################################################################
# FILE SYSTEM PREPARATION
################################################################################

# Create data directories with error checking
if ! mkdir -p "$DATA_DIR" "$TEAM_IMAGES_DIR"; then
    error "Failed to create data directories $DATA_DIR and $TEAM_IMAGES_DIR"
    exit 1
fi

# Validate data-manifest file exists
if [ ! -f "$WORKING_DIR/data-manifest.json" ]; then
    error "data-manifest.json not found in $WORKING_DIR"
    exit 1
fi

################################################################################
# MANIFEST PARSING AND CONFIGURATION
################################################################################

parse_manifest_data "$WORKING_DIR/data-manifest.json"

log "$BRANCH branch, DATA_VERSION = $DATA_VERSION, manifest id = $DATA_FILE"

# Display what will be processed
log "=== Import Configuration ==="
log "Expected collections after import: ${EXPECTED_COLLECTIONS[*]}"
log "==============================="

################################################################################
# SYNAPSE DATA DOWNLOAD
################################################################################

# Validate Synapse CLI is available
if ! validate_synapse_cli; then
    exit 1
fi

# Start synapse operations timing
SYNAPSE_START_TIME=$(date +%s)

# Download all Synapse data
if ! download_synapse_data "$SYNAPSE_PASSWORD" "$DATA_DIR" "$DATA_VERSION" "$DATA_FILE"; then
    exit 1
fi

# Download team images
if ! download_team_images "$SYNAPSE_PASSWORD" "$TEAM_IMAGES_DIR" "$TEAM_IMAGES_ID"; then
    exit 1
fi

# Calculate synapse download time
SYNAPSE_END_TIME=$(date +%s)
SYNAPSE_DURATION=$((SYNAPSE_END_TIME - SYNAPSE_START_TIME))

# List downloaded files for verification
list_downloaded_files "$WORKING_DIR" "$DATA_DIR" "$TEAM_IMAGES_DIR"

################################################################################
# DATABASE OPERATIONS
################################################################################

# Check if dataversion exists and handle different data format
DATAVERSION_PATH="${DATA_DIR}/dataversion.json"
DATAVERSION_FLAG="--jsonArray"
if [ ! -f "${DATAVERSION_PATH}" ]; then
  DATAVERSION_PATH="${WORKING_DIR}/data-manifest.json"
  DATAVERSION_FLAG=""
fi

# Test database connectivity
if ! test_database_connection "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS"; then
    exit 1
fi

# Start database operations timing
DB_START_TIME=$(date +%s)

log_database_storage "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "before import"

# Clear any staging collections a previously failed run left behind
drop_staging_collections "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS"

# Clean up orphaned collections before import
cleanup_orphaned_collections "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "${EXPECTED_COLLECTIONS[@]}"

################################################################################
# DATA IMPORT
################################################################################

# Import synapse data to database
# Everything is loaded and indexed in staging collections first, so the live
# collections keep serving the previous release until the swap below
log "Starting MongoDB data import into staging collections..."

# Import collections from array
for entry in "${COLLECTIONS[@]}"; do
    collection="${entry%%:*}"
    file="${DATA_DIR}/${entry#*:}"
    import_staging_collection "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "$collection" "$file" "--jsonArray"
done

log "Importing dataversion from ${DATAVERSION_PATH}"
import_staging_collection "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "dataversion" "$DATAVERSION_PATH" "$DATAVERSION_FLAG"

# Create indexes on the staging collections, before they are swapped in
create_staging_indexes "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "$WORKING_DIR/create-indexes.js"

# Upload team images into staging collections, so they replace the previous
# release's images when swapped in
import_staging_team_images "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "$DB_NAME" "$TEAM_IMAGES_DIR"

################################################################################
# ATOMIC SWAP
################################################################################

# The live collections are only touched from here on, once every staging
# collection has loaded, so any failure above leaves the previous release live
verify_staging_collections "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "${EXPECTED_COLLECTIONS[@]}"

swap_staging_collections "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "${EXPECTED_COLLECTIONS[@]}"

log_database_storage "$MONGO_URI" "$MONGO_USER" "$MONGO_PASS" "after swap"

################################################################################
# COMPLETION AND SUMMARY
################################################################################

# Calculate database operations time
DB_END_TIME=$(date +%s)
DB_DURATION=$((DB_END_TIME - DB_START_TIME))

# Calculate total script time
SCRIPT_END_TIME=$(date +%s)
SCRIPT_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

log "=== Execution Time Summary ==="
log_time "$SYNAPSE_DURATION" "Synapse downloads"
log_time "$DB_DURATION" "Database operations"
log_time "$SCRIPT_DURATION" "Total script execution"
log "=============================="
log "Data import completed successfully!"
