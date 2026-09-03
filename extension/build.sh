#!/bin/bash

# Build script for Omi RSS Extension

echo "Building Omi RSS Extension..."

# Create build directories
mkdir -p build/chrome
mkdir -p build/firefox

# Copy common files
echo "Copying common files..."
cp -r css build/chrome/
cp -r css build/firefox/
cp -r js build/chrome/
cp -r js build/firefox/
cp -r icons build/chrome/
cp -r icons build/firefox/
cp *.html build/chrome/
cp *.html build/firefox/

# Copy Chrome manifest
echo "Building Chrome version..."
cp manifest.json build/chrome/

# Copy Firefox manifest
echo "Building Firefox version..."
cp manifest_firefox.json build/firefox/manifest.json

# Create zip files
echo "Creating extension packages..."
cd build/chrome
zip -r ../omi-rss-chrome.zip *
cd ../firefox
zip -r ../omi-rss-firefox.zip *
cd ../..

echo "Build complete!"
echo "Chrome extension: build/omi-rss-chrome.zip"
echo "Firefox extension: build/omi-rss-firefox.zip"