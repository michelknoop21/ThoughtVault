#!/bin/bash
# Test the transcribe endpoint with curl to verify server behavior

# This script tests the server with a known-good multipart request
# Usage: ./test_upload.sh <path-to-wav-file> <token>

if [ $# -lt 2 ]; then
    echo "Usage: $0 <wav-file> <token>"
    exit 1
fi

WAV_FILE="$1"
TOKEN="$2"
URL="https://n8n.prezent.nl/tstudio/api/transcribe"

if [ ! -f "$WAV_FILE" ]; then
    echo "File not found: $WAV_FILE"
    exit 1
fi

echo "Testing upload to: $URL"
echo "File: $WAV_FILE"
echo "Token: ${TOKEN:0:10}..."

# Test with curl using multipart/form-data
curl -v \
  -X POST \
  -H "X-User-Token: $TOKEN" \
  -F "file=@$WAV_FILE;type=audio/wav" \
  -F "profile_id=zakelijk" \
  "$URL"
