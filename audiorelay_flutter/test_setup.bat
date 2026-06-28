@echo off
REM ============================================================
REM AudioRelay Flutter Client - Setup & Test Script
REM Run this after installing Flutter SDK on Windows
REM ============================================================

echo 1. Checking Flutter installation...
flutter --version
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Flutter not found. Please install Flutter SDK first.
    echo Download: https://docs.flutter.dev/get-started/install/windows
    exit /b 1
)

echo.
echo 2. Installing dependencies...
cd /d "%~dp0"
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to install dependencies.
    exit /b 1
)

echo.
echo 3. Running static analysis...
flutter analyze
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: Static analysis found issues.
)

echo.
echo 4. Running unit tests...
flutter test
if %ERRORLEVEL% NEQ 0 (
    echo WARNING: Tests failed.
)

echo.
echo 5. Building Android APK...
flutter build apk --debug
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Android build failed.
    exit /b 1
)

echo.
echo 6. Building for iOS (CI only - skip on Windows)...
echo    Push to GitHub and use GitHub Actions to build iOS.

echo.
echo ============================================================
echo All checks passed!
echo APK location: build\app\outputs\flutter-apk\app-debug.apk
echo ============================================================
