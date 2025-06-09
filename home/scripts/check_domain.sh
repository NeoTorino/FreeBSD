#!/bin/sh

# Check if dig is installed
if ! command -v dig >/dev/null 2>&1; then
  echo "This script requires 'dig'. Please install it and try again."
  exit 1
fi

if [ $# -ne 1 ]; then
  echo "Usage: sh check_domain.sh <domain-or-subdomain>"
  exit 1
fi

INPUT_DOMAIN="$1"

# Function to extract base domain (second-level + TLD) from input
get_base_domain() {
  # This is a simple heuristic; for complex TLDs like co.uk, you may need a public suffix list
  # Here we take the last two labels, e.g. example.com from sub.example.com
  echo "$1" | awk -F. '{print $(NF-1)"."$NF}'
}

BASE_DOMAIN=$(get_base_domain "$INPUT_DOMAIN")

CURRENT="$INPUT_DOMAIN"
DEPTH=0
MAX_DEPTH=10
DANGLING=0

echo "Checking domain: $INPUT_DOMAIN"
echo "----------------------------------"

# Step 1 - Follow CNAME chain and find IPs for the full input domain
while [ $DEPTH -lt $MAX_DEPTH ]; do
  echo "Step $((DEPTH+1)): Looking up '$CURRENT'..."

  IPS=$(dig +short "$CURRENT" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

  if [ -n "$IPS" ]; then
    echo "✅ Found IP address(es) for '$CURRENT':"
    echo "$IPS" | while read IP; do
      echo "   - $IP"
    done
    break
  fi

  CNAME=$(dig +short "$CURRENT" CNAME | sed 's/\.$//')

  if [ -n "$CNAME" ]; then
    echo "🔁 '$CURRENT' is a CNAME pointing to: $CNAME"
    CURRENT="$CNAME"
    DEPTH=$((DEPTH + 1))
  else
    echo "⚠️ No IP address or CNAME found for '$CURRENT'."
    echo "🚨 '$CURRENT' may be a dangling domain — unassigned and at risk."
    DANGLING=1
    break
  fi
done

if [ $DEPTH -eq $MAX_DEPTH ]; then
  echo "❌ Too many redirects (possible CNAME loop)."
fi

echo
echo "Now checking Name Servers (NS) and AXFR (Zone Transfer) for base domain: $BASE_DOMAIN"
echo "---------------------------------------------------------------------------------------"

NS_SERVERS=$(dig +short NS "$BASE_DOMAIN" | sed 's/\.$//')

if [ -z "$NS_SERVERS" ]; then
  echo "⚠️ No NS records found for $BASE_DOMAIN."
else
  echo "Found NS servers for $BASE_DOMAIN:"
  echo "$NS_SERVERS" | while read NS; do
    echo " - $NS"
  done
fi

echo

# Test AXFR on each NS server for the base domain
for NS in $NS_SERVERS; do
  echo "Testing zone transfer (AXFR) on NS server: $NS"

  AXFR_RESULT=$(timeout 10 dig AXFR "$BASE_DOMAIN" @"$NS" 2>&1)

  if echo "$AXFR_RESULT" | grep -q "Transfer failed"; then
    echo "   ❌ Zone transfer NOT allowed (Transfer failed)."
  elif echo "$AXFR_RESULT" | grep -q "connection refused"; then
    echo "   ❌ Zone transfer NOT allowed (Connection refused)."
  elif echo "$AXFR_RESULT" | grep -q "connection reset"; then
    echo "   ❌ Zone transfer NOT allowed (Connection reset)."
  elif echo "$AXFR_RESULT" | grep -q "no servers could be reached"; then
    echo "   ❌ Zone transfer NOT allowed (No servers could be reached)."
  elif echo "$AXFR_RESULT" | grep -q "timed out"; then
    echo "   ❌ Zone transfer NOT allowed (Timed out)."
  else
    RECORDS_LINES=$(echo "$AXFR_RESULT" | grep -v '^;')
    if [ -n "$RECORDS_LINES" ]; then
      echo "   ✅ Zone transfer succeeded! Sample records:"
      echo "$RECORDS_LINES" | head -n 10 | sed 's/^/      /'
    else
      echo "   ❌ Zone transfer NOT allowed or no data returned."
    fi
  fi

  echo
done

echo "All checks completed."

# Exit code 1 if dangling domain detected, else 0
if [ $DANGLING -eq 1 ]; then
  exit 1
else
  exit 0
fi
