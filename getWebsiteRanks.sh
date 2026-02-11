#!/usr/bin/env bash

set -uo pipefail
set -a; source .env; set +a

OUTPUT_FILE="top250websites.json"
TMP_DIR="temp"
mkdir -p "$TMP_DIR"
DOMAINS_FILE="$TMP_DIR/domains.txt"
RESULTS_FILE="$TMP_DIR/results.jsonl"

echo "--- Downloading Tranco top sites list..."
curl -L "https://tranco-list.eu/top-1m.csv.zip" -o "$TMP_DIR/top-1m.csv.zip"

echo "--- Extracting and normalizing top 500 websites..."
unzip -p "$TMP_DIR/top-1m.csv.zip" top-1m.csv \
    | head -n 500 \
    | cut -d',' -f2 \
    | sed 's/^www\.//g' \
    > "$DOMAINS_FILE"

echo "...done"

echo "--- Querying OPR API..."

# Clear results file if it exists
> "$RESULTS_FILE"

BATCH_SIZE=100
split -l $BATCH_SIZE "$DOMAINS_FILE" "$TMP_DIR/batch_"

for BATCH in "$TMP_DIR"/batch_*; do
    # Build query string - properly handle newlines
    QUERY_STRING=""
    while IFS= read -r DOMAIN; do
        # Trim any whitespace/newlines
        DOMAIN=$(echo "$DOMAIN" | tr -d '\n\r' | xargs)
        
        if [ -n "$DOMAIN" ]; then
            # URL encode the domain and append
            ENCODED=$(printf %s "$DOMAIN" | jq -sRr @uri)
            QUERY_STRING="${QUERY_STRING}domains[]=${ENCODED}&"
        fi
    done < "$BATCH"
    
    # Remove trailing &
    QUERY_STRING="${QUERY_STRING%&}"

    echo "Processing batch (first 3 domains)..."
    echo "$QUERY_STRING" | cut -d'&' -f1-3
    
    RESPONSE=$(curl -s "https://openpagerank.com/api/v1.0/getPageRank?${QUERY_STRING}" \
        -H "API-OPR: $API_KEY")
    
    # Validate JSON before appending
    if echo "$RESPONSE" | jq empty 2>/dev/null; then
        echo "$RESPONSE" >> "$RESULTS_FILE"
        
        # Check for errors
        ERROR_COUNT=$(echo "$RESPONSE" | jq '[.response[] | select(.status_code == 400)] | length')
        SUCCESS_COUNT=$(echo "$RESPONSE" | jq '[.response[] | select(.status_code == 200)] | length')
        echo "✓ Batch processed - Successes: $SUCCESS_COUNT, Errors: $ERROR_COUNT"
    else
        echo "✗ Invalid JSON response"
        echo "Response: $RESPONSE"
    fi
    
    sleep 1
done

echo "...done"

echo "--- Merging results to $OUTPUT_FILE..."
jq -s '{
    status: "success",
    total_batches: length,
    results: [ .[].response[] ],
    successful_results: [ .[].response[] | select(.status_code == 200) ],
    failed_results: [ .[].response[] | select(.status_code == 400) ]
}' "$RESULTS_FILE" > "$OUTPUT_FILE"

echo "...done"
echo "--- Results saved to $OUTPUT_FILE"

# Show summary
jq '{
    status,
    total_batches,
    total_results: (.results | length),
    successful: (.successful_results | length),
    failed: (.failed_results | length)
}' "$OUTPUT_FILE"