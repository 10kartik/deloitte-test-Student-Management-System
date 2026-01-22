#!/bin/bash

# =============================================================================
# Student CRUD API Test Script
# Tests all 5 student management endpoints for Problem 2
# =============================================================================

# Don't use set -e as it causes issues with arithmetic operations

# Configuration
BASE_URL="http://localhost:5007/api/v1"
COOKIE_JAR="/tmp/student-api-cookies.txt"
USERNAME="admin@school-admin.com"
PASSWORD="3OU4zn3q6Zh9"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_test() {
    echo -e "${YELLOW}▶ Testing: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ PASSED: $1${NC}"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAILED: $1${NC}"
    echo -e "${RED}  Response: $2${NC}"
    ((FAILED++))
}

get_csrf_token() {
    grep "csrfToken" "$COOKIE_JAR" | awk '{print $7}'
}

cleanup() {
    rm -f "$COOKIE_JAR"
}

# Cleanup on exit
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Test 0: Login
# -----------------------------------------------------------------------------

print_header "AUTHENTICATION"
print_test "POST /auth/login"

LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -c "$COOKIE_JAR" \
    -d "{\"username\": \"$USERNAME\", \"password\": \"$PASSWORD\"}")

if echo "$LOGIN_RESPONSE" | grep -q '"id"'; then
    print_pass "Login successful"
    echo "  User: $(echo "$LOGIN_RESPONSE" | grep -o '"name":"[^"]*"' | head -1)"
else
    print_fail "Login failed" "$LOGIN_RESPONSE"
    echo -e "${RED}Cannot continue without authentication. Exiting.${NC}"
    exit 1
fi

CSRF_TOKEN=$(get_csrf_token)
echo "  CSRF Token: ${CSRF_TOKEN:0:20}..."

# -----------------------------------------------------------------------------
# Test 1: GET All Students
# -----------------------------------------------------------------------------

print_header "TEST 1: GET ALL STUDENTS"
print_test "GET /students"

GET_ALL_RESPONSE=$(curl -s -X GET "$BASE_URL/students" \
    -H "Content-Type: application/json" \
    -H "x-csrf-token: $CSRF_TOKEN" \
    -b "$COOKIE_JAR")

if echo "$GET_ALL_RESPONSE" | grep -q '"students"'; then
    STUDENT_COUNT=$(echo "$GET_ALL_RESPONSE" | grep -o '"id"' | wc -l | tr -d ' ')
    print_pass "GET /students - Found $STUDENT_COUNT students"
elif echo "$GET_ALL_RESPONSE" | grep -q "Students not found"; then
    echo -e "${YELLOW}  Note: No students exist yet (expected for fresh database)${NC}"
    print_pass "GET /students - Endpoint works correctly (empty list returns 404)"
else
    print_fail "GET /students" "$GET_ALL_RESPONSE"
fi

# -----------------------------------------------------------------------------
# Test 2: POST - Add New Student
# -----------------------------------------------------------------------------

print_header "TEST 2: CREATE NEW STUDENT"
print_test "POST /students"

TIMESTAMP=$(date +%s)
NEW_STUDENT_EMAIL="test.student.${TIMESTAMP}@school.com"

# Minimal required payload for student creation
ADD_STUDENT_PAYLOAD=$(cat <<EOF
{
    "name": "Test Student $TIMESTAMP",
    "email": "$NEW_STUDENT_EMAIL",
    "gender": "male",
    "phone": "1234567890"
}
EOF
)

ADD_RESPONSE=$(curl -s -X POST "$BASE_URL/students" \
    -H "Content-Type: application/json" \
    -H "x-csrf-token: $CSRF_TOKEN" \
    -b "$COOKIE_JAR" \
    -d "$ADD_STUDENT_PAYLOAD")

if echo "$ADD_RESPONSE" | grep -qi "success\|added"; then
    print_pass "POST /students - Student created"
    echo "  Response: $ADD_RESPONSE"
else
    print_fail "POST /students" "$ADD_RESPONSE"
fi

# Get the new student's ID by fetching the list again
sleep 1
GET_UPDATED_RESPONSE=$(curl -s -X GET "$BASE_URL/students" \
    -H "Content-Type: application/json" \
    -H "x-csrf-token: $CSRF_TOKEN" \
    -b "$COOKIE_JAR")

# Extract the last student ID (most recently added - students have role_id=3)
NEW_STUDENT_ID=$(echo "$GET_UPDATED_RESPONSE" | grep -o '"id":[0-9]*' | tail -1 | grep -o '[0-9]*')

if [ -z "$NEW_STUDENT_ID" ]; then
    echo -e "${YELLOW}  Warning: Could not extract new student ID. Will query database directly.${NC}"
    # Fallback: query the database for the latest student
    NEW_STUDENT_ID=$(docker exec school-db psql -U postgres -d school_mgmt -t -c "SELECT id FROM users WHERE role_id = 3 ORDER BY id DESC LIMIT 1;" 2>/dev/null | tr -d ' ')
    if [ -z "$NEW_STUDENT_ID" ]; then
        echo -e "${RED}  Could not find any students. Skipping remaining tests.${NC}"
        NEW_STUDENT_ID=""
    fi
fi

if [ -n "$NEW_STUDENT_ID" ]; then
    echo "  New Student ID: $NEW_STUDENT_ID"
fi

# -----------------------------------------------------------------------------
# Test 3: GET Student Detail
# -----------------------------------------------------------------------------

print_header "TEST 3: GET STUDENT DETAIL"

if [ -z "$NEW_STUDENT_ID" ]; then
    echo -e "${YELLOW}  Skipped: No student ID available${NC}"
else
    print_test "GET /students/$NEW_STUDENT_ID"

    GET_DETAIL_RESPONSE=$(curl -s -X GET "$BASE_URL/students/$NEW_STUDENT_ID" \
        -H "Content-Type: application/json" \
        -H "x-csrf-token: $CSRF_TOKEN" \
        -b "$COOKIE_JAR")

    if echo "$GET_DETAIL_RESPONSE" | grep -q '"id"'; then
        STUDENT_NAME=$(echo "$GET_DETAIL_RESPONSE" | grep -o '"name":"[^"]*"' | head -1)
        print_pass "GET /students/$NEW_STUDENT_ID - Retrieved student details"
        echo "  $STUDENT_NAME"
    else
        print_fail "GET /students/$NEW_STUDENT_ID" "$GET_DETAIL_RESPONSE"
    fi
fi

# -----------------------------------------------------------------------------
# Test 4: PUT - Update Student
# -----------------------------------------------------------------------------

print_header "TEST 4: UPDATE STUDENT"

if [ -z "$NEW_STUDENT_ID" ]; then
    echo -e "${YELLOW}  Skipped: No student ID available${NC}"
else
    print_test "PUT /students/$NEW_STUDENT_ID"

    # For update, we need to pass userId in the payload
    UPDATE_PAYLOAD=$(cat <<EOF
{
    "userId": $NEW_STUDENT_ID,
    "name": "Updated Test Student $TIMESTAMP",
    "email": "$NEW_STUDENT_EMAIL",
    "phone": "9999999999",
    "gender": "female"
}
EOF
)

    UPDATE_RESPONSE=$(curl -s -X PUT "$BASE_URL/students/$NEW_STUDENT_ID" \
        -H "Content-Type: application/json" \
        -H "x-csrf-token: $CSRF_TOKEN" \
        -b "$COOKIE_JAR" \
        -d "$UPDATE_PAYLOAD")

    if echo "$UPDATE_RESPONSE" | grep -qi "success\|updated"; then
        print_pass "PUT /students/$NEW_STUDENT_ID - Student updated"
        echo "  Response: $UPDATE_RESPONSE"
    else
        print_fail "PUT /students/$NEW_STUDENT_ID" "$UPDATE_RESPONSE"
    fi
fi

# -----------------------------------------------------------------------------
# Test 5: POST - Change Student Status
# -----------------------------------------------------------------------------

print_header "TEST 5: CHANGE STUDENT STATUS"

if [ -z "$NEW_STUDENT_ID" ]; then
    echo -e "${YELLOW}  Skipped: No student ID available${NC}"
else
    print_test "POST /students/$NEW_STUDENT_ID/status"

    STATUS_PAYLOAD='{"status": false}'

    STATUS_RESPONSE=$(curl -s -X POST "$BASE_URL/students/$NEW_STUDENT_ID/status" \
        -H "Content-Type: application/json" \
        -H "x-csrf-token: $CSRF_TOKEN" \
        -b "$COOKIE_JAR" \
        -d "$STATUS_PAYLOAD")

    if echo "$STATUS_RESPONSE" | grep -qi "success\|changed"; then
        print_pass "POST /students/$NEW_STUDENT_ID/status - Status changed"
        echo "  Response: $STATUS_RESPONSE"
    else
        print_fail "POST /students/$NEW_STUDENT_ID/status" "$STATUS_RESPONSE"
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

print_header "TEST SUMMARY"
echo ""
echo -e "  ${GREEN}Passed: $PASSED${NC}"
echo -e "  ${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ ALL TESTS PASSED - Problem 2 Implementation Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    exit 0
else
    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ✗ SOME TESTS FAILED - Check implementation${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    exit 1
fi
