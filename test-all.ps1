# test-all.ps1
# A comprehensive test script for the final KrakenD + Keycloak setup.
# It tests all endpoints (including login) with different user roles.

# --- Configuration ---
# All requests go through the KrakenD Gateway
$GatewayUrl = "http://localhost:8081"
$LoginUrl   = "$GatewayUrl/login"

# --- Helper Function to Print Headers ---
function Print-Header {
    param([string]$Title)
    Write-Host "`n"
    Write-Host ("-" * 70)
    Write-Host "➡️  $Title"
    Write-Host ("-" * 70)
}

# --- Script Body ---
# Wait for the gateway to be ready
Write-Host "⏳ Waiting for KrakenD Gateway to be ready at $GatewayUrl/public..." -NoNewline
while ($true) {
    try {
        Invoke-RestMethod -Uri "$GatewayUrl/public" -ErrorAction Stop | Out-Null
        Write-Host " ✅" -ForegroundColor Green
        break
    }
    catch {
        Write-Host -NoNewline "."
        Start-Sleep 2
    }
}

# --- Phase 1: Get Tokens via /login ---
Print-Header "Phase 1: Acquiring JWTs for Alice (user) and Bob (admin) via /login"

# Get Token for Alice
try {
    $aliceLoginResponse = Invoke-RestMethod -Method Post `
      -Uri $LoginUrl `
      -ContentType "application/x-www-form-urlencoded" `
      -Body @{ grant_type = 'password'; client_id = 'fiber-app'; username = 'alice'; password = 'password123' } `
      -ErrorAction Stop

    $alice_token = $aliceLoginResponse.access_token
    Write-Host "✅ SUCCESS: Got token for Alice." -ForegroundColor Green
} catch {
    Write-Host "❌ FAILED: Could not get token for Alice. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get Token for Bob
try {
    $bobLoginResponse = Invoke-RestMethod -Method Post `
      -Uri $LoginUrl `
      -ContentType "application/x-www-form-urlencoded" `
      -Body @{ grant_type = 'password'; client_id = 'fiber-app'; username = 'bob'; password = 'password123' } `
      -ErrorAction Stop

    $bob_token = $bobLoginResponse.access_token
    Write-Host "✅ SUCCESS: Got token for Bob." -ForegroundColor Green
} catch {
    Write-Host "❌ FAILED: Could not get token for Bob. Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Phase 2: Test Public Endpoint (/public) ---
Print-Header "Phase 2: Testing Public Endpoint (/public)"
$publicResponse = Invoke-RestMethod -Uri "$GatewayUrl/public"
if ($publicResponse.message -eq "This is a public endpoint.") {
    Write-Host "✅ SUCCESS: Public endpoint is accessible and returned correct message." -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: Public endpoint returned unexpected data." -ForegroundColor Red
}

# --- Phase 3: Test Protected Endpoint (/profile) ---
Print-Header "Phase 3: Testing Protected Endpoint (/profile)"

# With a valid token (should succeed)
$profileResponse = Invoke-RestMethod -Uri "$GatewayUrl/profile" -Headers @{ "Authorization" = "Bearer $alice_token" }
if ($profileResponse.message -like "Hello, alice*") {
    Write-Host "✅ SUCCESS: /profile is accessible with a valid token." -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: /profile returned unexpected data with a valid token." -ForegroundColor Red
}

# Without a token (should fail with 401)
try {
    Invoke-RestMethod -Uri "$GatewayUrl/profile" -ErrorAction Stop
    Write-Host "❌ FAILED: /profile was accessible without a token. SECURITY RISK!" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq "Unauthorized") {
        Write-Host "✅ SUCCESS: /profile correctly blocked request without a token (401 Unauthorized)." -ForegroundColor Green
    } else {
        Write-Host "❌ FAILED: /profile blocked request, but with unexpected status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# --- Phase 4: Test Role-Based Endpoint (/user) ---
Print-Header "Phase 4: Testing Role-Based Endpoint (/user)"

# With Alice (has 'user' role, should succeed)
$userResponse = Invoke-RestMethod -Uri "$GatewayUrl/user" -Headers @{ "Authorization" = "Bearer $alice_token" }
if ($userResponse.message -eq "Hello, user-level endpoint!") {
    Write-Host "✅ SUCCESS: Alice (role: user) can access /user." -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: /user returned unexpected data for Alice." -ForegroundColor Red
}

# With Bob (only 'admin' role, should fail with 403)
try {
    Invoke-RestMethod -Uri "$GatewayUrl/user" -Headers @{ "Authorization" = "Bearer $bob_token" } -ErrorAction Stop
    Write-Host "❌ FAILED: Bob (role: admin) was able to access /user. Role check failed!" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq "Forbidden") {
        Write-Host "✅ SUCCESS: Bob (role: admin) was correctly blocked from /user (403 Forbidden)." -ForegroundColor Green
    } else {
        Write-Host "❌ FAILED: Bob was blocked from /user, but with unexpected status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# --- Phase 5: Test Role-Based Endpoint (/admin) ---
Print-Header "Phase 5: Testing Role-Based Endpoint (/admin)"

# With Alice (does not have 'admin' role, should fail with 403)
try {
    Invoke-RestMethod -Uri "$GatewayUrl/admin" -Headers @{ "Authorization" = "Bearer $alice_token" } -ErrorAction Stop
    Write-Host "❌ FAILED: Alice (role: user) was able to access /admin. Role check failed!" -ForegroundColor Red
} catch {
    if ($_.Exception.Response.StatusCode -eq "Forbidden") {
        Write-Host "✅ SUCCESS: Alice (role: user) was correctly blocked from /admin (403 Forbidden)." -ForegroundColor Green
    } else {
        Write-Host "❌ FAILED: Alice was blocked from /admin, but with unexpected status: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    }
}

# With Bob (has 'admin' role, should succeed)
$adminResponse = Invoke-RestMethod -Uri "$GatewayUrl/admin" -Headers @{ "Authorization" = "Bearer $bob_token" }
if ($adminResponse.message -eq "Hello, admin-level endpoint!") {
    Write-Host "✅ SUCCESS: Bob (role: admin) can access /admin." -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: /admin returned unexpected data for Bob." -ForegroundColor Red
}

Write-Host "`n"
Write-Host ("-" * 70)
Write-Host "🎉 All tests complete. The system is working as expected! 🎉"
Write-Host ("-" * 70)
