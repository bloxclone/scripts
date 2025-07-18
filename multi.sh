#!/bin/bash

echo "Enter one or more combos [API_TOKEN]/[ORG_SLUG], one per line. Press Ctrl+D when done:"

# Read all lines into an array
mapfile -t combos

get_tailscale_auth_key() {
  local OAUTH_TOKEN="tskey-api-kWHuFCpgE811CNTRL-hTSQhCsVSyhtt4ufY8yTyhSARYvrrevDd"
  local TAILNET="tail097da5.ts.net"

  local RESPONSE=$(curl -s -X POST "https://api.tailscale.com/api/v2/tailnet/$TAILNET/keys" \
    -H "Authorization: Bearer $OAUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "capabilities": {
        "devices": {
          "create": {
            "reusable": true,
            "ephemeral": true,
            "preauthorized": true
          }
        }
      },
      "description": "Auto-generated key for pipelines",
      "expires": "24h"
    }')

  local AUTH_KEY=$(echo "$RESPONSE" | grep -o '"key": *"[^"]*"' | sed -E 's/"key": *"([^"]*)"/\1/')
  if [[ -z "$AUTH_KEY" ]]; then
    echo "❌ Failed to get Tailscale auth key." >&2
    echo "$RESPONSE" >&2
    exit 1
  fi

  echo "$AUTH_KEY"
}


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

  echo "generating auth key for tailscale..."
  KEY=$(get_tailscale_auth_key)

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
  "configuration": "steps:\n  - label: \":pipeline:\"\n    commands:\n      - curl -fsSL https://tailscale.com/install.sh | sh\n      - sudo apt-get install -y tailscale\n      - sudo tailscaled &\n      - sleep 2\n      - sudo tailscale up --ssh --auth-key=$KEY\n      - sleep infinity"
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
