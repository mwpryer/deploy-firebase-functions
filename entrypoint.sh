#!/bin/sh

set -e

PROJECT_ID="$1"
FUNCTIONS_DIR="$2"
FORCE="$3"
DEBUG="$4"

# Validate inputs
if [ -z "$PROJECT_ID" ]; then
  echo "PROJECT_ID is missing"
  exit 1
fi
if [ ! -d "$FUNCTIONS_DIR" ]; then
  echo "Directory $FUNCTIONS_DIR not found"
  exit 1
fi

# Install dependencies in case of pre-deploy steps
cd "$FUNCTIONS_DIR"
npm ci

# Prepare deploy command
DEPLOY_CMD="firebase deploy --only functions --project $PROJECT_ID --non-interactive"
if [ "$FORCE" = "true" ]; then
  DEPLOY_CMD="$DEPLOY_CMD --force"
fi
if [ "$DEBUG" = "true" ]; then
  DEPLOY_CMD="$DEPLOY_CMD --debug"
fi

# Deploy
eval "$DEPLOY_CMD"
