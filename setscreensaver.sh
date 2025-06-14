#!/bin/bash
#-----------------------
# FILL IN YOUR DETAILS HERE
#-----------------------

MY_BUCKET="wallpaper-collection"
IMAGES_FOLDER="$HOME/Documents/MyBackgroundImages"

#-----------------------
# - Install AWS CLI
#-----------------------
# Check if AWS CLI is installed, if not, install it            
echo "Installing AWS CLI..."
if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI not found"
    brew install awscli
    
    # Wait for installation to complete
    while ! command -v aws >/dev/null 2>&1; do
        echo "Waiting for AWS CLI installation..."
        sleep 2
    done
    echo "AWS CLI installed successfully."
else
    echo "AWS CLI is already installed."
fi
# Check AWS configuration
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "AWS not configured. Please run 'aws configure' first."
    exit 1
fi

#-----------------------
# - Download Images
#-----------------------

echo "Creating folder and downloading images..."
mkdir -p "$IMAGES_FOLDER"

# TODO: Download all images from your bucket
aws s3 sync "s3://$MY_BUCKET" "$IMAGES_FOLDER"
if [ $? -eq 0 ]; then
    echo "Images downloaded successfully"
    ls -la "$IMAGES_FOLDER"  # Show what was downloaded
else
    echo "Error downloading images"
    exit 1
fi

#-----------------------
# - Set Screensaver
#-----------------------
echo "Setting desktop background..."

IMAGES=($(find "$IMAGES_FOLDER" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | head -10))

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo "No images found in $IMAGES_FOLDER"
    exit 1
fi

# Set different wallpaper for each desktop/display
osascript <<EOF
tell application "System Events"
    set imageList to {"${IMAGES[0]}", "${IMAGES[1]}", "${IMAGES[2]}", "${IMAGES[3]}"}
    set desktopCount to count of desktops
    
    repeat with i from 1 to desktopCount
        set imageIndex to ((i - 1) mod (count of imageList)) + 1
        set picture of desktop i to (imageList's item imageIndex)
        log "Set desktop " & i & " to image " & imageIndex
    end repeat
end tell
EOF

echo "Set different wallpapers for each display!"