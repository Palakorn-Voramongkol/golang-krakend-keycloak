#!/usr/bin/env bash
# test-all.sh
# A comprehensive test script for the final KrakenD + Keycloak setup.
# It tests all endpoints (including login) with different user roles.

set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---
GatewayUrl="http://localhost:8081"
LoginUrl="$GatewayUrl/login"

# ANSI colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # no color

# --- Helper Function to Print Headers ---
print_header() {
  title="$1"
  printf "\n%.0s-" {1..70}
  printf "\n➡️  %s\n" "$title"
  printf "%.0s-" {1..70}
  echo
}

# --- Wait for the gateway to be ready ---
printf "⏳ Waiting for KrakenD Gateway at %s/public..." "$GatewayUrl"
until curl -s "$GatewayUrl/public" > /dev/null; do
  printf "."
  sleep 2
done
printf " ${GREEN}✅${NC}\n"

# Track failures
failures=0

# --- Phase 1: Get Tokens via /login ---
print_header "Phase 1: Acquiring JWTs for Alice (user) and Bob (admin) via /login"

# Alice
if alice_token=$(curl -s -X POST "$LoginUrl" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data "grant_type=password&client_id=fiber-app&username=alice&password=password123" \
  | jq -r '.access_token'); then
  if [[ -n "$alice_token" && "$alice_token" != "null" ]]; then
    printf "${GREEN}✅ SUCCESS${NC}: Got token for Alice.\n"
  else
    printf "${RED}❌ FAILED${NC}: No token received for Alice.\n"
    failures=$((failures+1))
  fi
else
  printf "${RED}❌ FAILED${NC}: Could not get token for Alice.\n"
  failures=$((failures+1))
fi

# Bob
if bob_token=$(curl -s -X POST "$LoginUrl" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data "grant_type=password&client_id=fiber-app&username=bob&password=password123" \
  | jq -r '.access_token'); then
  if [[ -n "$bob_token" && "$bob_token" != "null" ]]; then
    printf "${GREEN}✅ SUCCESS${NC}: Got token for Bob.\n"
  else
    printf "${RED}❌ FAILED${NC}: No token received for Bob.\n"
    failures=$((failures+1))
  fi
else
  printf "${RED}❌ FAILED${NC}: Could not get token for Bob.\n"
  failures=$((failures+1))
fi

# --- Phase 2: Test Public Endpoint (/public) ---
print_header "Phase 2: Testing Public Endpoint (/public)"
public_msg=$(curl -s "$GatewayUrl/public" | jq -r '.message')
if [[ "$public_msg" == "This is a public endpoint." ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: Public endpoint is accessible and returned correct message.\n"
else
  printf "${RED}❌ FAILED${NC}: Public endpoint returned unexpected data: %s\n" "$public_msg"
  failures=$((failures+1))
fi

# --- Phase 3: Test Protected Endpoint (/profile) ---
print_header "Phase 3: Testing Protected Endpoint (/profile)"

# With a valid token (should succeed)
profile_msg=$(curl -s -H "Authorization: Bearer $alice_token" "$GatewayUrl/profile" | jq -r '.message')
if [[ "$profile_msg" == Hello,\ alice* ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: /profile is accessible with a valid token.\n"
else
  printf "${RED}❌ FAILED${NC}: /profile returned unexpected data with a valid token: %s\n" "$profile_msg"
  failures=$((failures+1))
fi

# Without a token (should fail with 401)
status=$(curl -s -o /dev/null -w '%{http_code}' "$GatewayUrl/profile")
if [[ "$status" -eq 401 ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: /profile correctly blocked request without a token (401 Unauthorized).\n"
else
  printf "${RED}❌ FAILED${NC}: /profile status without token was %s, expected 401.\n" "$status"
  failures=$((failures+1))
fi

# --- Phase 4: Test Role-Based Endpoint (/user) ---
print_header "Phase 4: Testing Role-Based Endpoint (/user)"

# With Alice (has 'user' role, should succeed)
user_msg=$(curl -s -H "Authorization: Bearer $alice_token" "$GatewayUrl/user" | jq -r '.message')
if [[ "$user_msg" == "Hello, user-level endpoint!" ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: Alice (role: user) can access /user.\n"
else
  printf "${RED}❌ FAILED${NC}: /user returned unexpected data for Alice: %s\n" "$user_msg"
  failures=$((failures+1))
fi

# With Bob (only 'admin' role, should fail with 403)
status=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $bob_token" "$GatewayUrl/user")
if [[ "$status" -eq 403 ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: Bob (role: admin) was correctly blocked from /user (403 Forbidden).\n"
else
  printf "${RED}❌ FAILED${NC}: /user status for Bob was %s, expected 403.\n" "$status"
  failures=$((failures+1))
fi

# --- Phase 5: Test Role-Based Endpoint (/admin) ---
print_header "Phase 5: Testing Role-Based Endpoint (/admin)"

# With Alice (does not have 'admin' role, should fail with 403)
status=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $alice_token" "$GatewayUrl/admin")
if [[ "$status" -eq 403 ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: Alice (role: user) was correctly blocked from /admin (403 Forbidden).\n"
else
  printf "${RED}❌ FAILED${NC}: /admin status for Alice was %s, expected 403.\n" "$status"
  failures=$((failures+1))
fi

# With Bob (has 'admin' role, should succeed)
admin_msg=$(curl -s -H "Authorization: Bearer $bob_token" "$GatewayUrl/admin" | jq -r '.message')
if [[ "$admin_msg" == "Hello, admin-level endpoint!" ]]; then
  printf "${GREEN}✅ SUCCESS${NC}: Bob (role: admin) can access /admin.\n"
else
  printf "${RED}❌ FAILED${NC}: /admin returned unexpected data for Bob: %s\n" "$admin_msg"
  failures=$((failures+1))
fi

printf "\n"
printf '%.0s-' {1..70}
echo

if [[ "$failures" -eq 0 ]]; then
  printf "${GREEN}🎉 All tests complete. The system is working as expected! 🎉${NC}\n"
  exit 0
else
  printf "${RED}⚠️  Some tests failed (%d failures).${NC}\n" "$failures"
  exit 1
fi
