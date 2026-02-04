#!/usr/bin/env bash

set -euo pipefail
set -a; source .env; set +a # get API key from .env

OUTPUT_FILE="top250websites.json"
TMP_DIR="temp"
DOMAINS_FILE="$TMP_DIR/domains.txt"
RESULTS_FILE="$TMP_DIR/results.json"

echo "--- Downloading Tranco top sites list..."
curl -L "https://tranco-list.eu/top-1m.csv.zip" -o "$TMP_DIR/tranco.csv.zip"

echo "--- Extracting top 250 websites..."
unzip -p "$TMP_DIR/tranco.csv.zip" \
    | head -n 250 \
    | cut -d',' -f2 \
    > "$DOMAINS_FILE"

mapfile -t DOMAINS < "$DOMAINS_FILE"
