# The Setup Engine

This is Automated setup script and workflow for new macOS installations. It installs your essential applications, configures system settings, and sets up personalized wallpapers from AWS S3.

## Features

- **Application Installation**: Installs common development and productivity apps via Homebrew
- **System Configuration**: Sets up dark mode, dock orientation, date/time formats
- **Custom Wallpapers**: Downloads and applies wallpapers from S3 bucket across multiple displays
- **Terminal Setup**: Configures iTerm2 with custom settings and installs Oh My Zsh
- **Debug Mode**: Test script without making changes

## Prerequisites

- macOS (tested on Apple Silicon and Intel)
- Internet connection
- AWS account with configured S3 bucket (for wallpapers) 

## Applications Installed

- Visual Studio Code
- Spotify
- Discord
- Rectangle (window management)
- iTerm2
- Karabiner Elements
- DisplayLink
- But you can add or change yours as long as they're in brew install --cask 

## Quick Start

1. **Clone or download the script**
2. **Set up AWS credentials** (if using wallpaper feature):
   ```bash
   aws configure
   ```
3. **Run the script**:
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```
4. **Choose debug mode** when prompted:
   - **Yes**: Test run without making changes
   - **No**: Full installation

## Configuration

### Wallpapers
Edit these variables in the script:
```bash
MY_BUCKET="your-bucket-name"
IMAGES_FOLDER="$HOME/Documents/MyBackgroundImages"
```

### Applications
Modify the applications array:
```bash
declare -a applications=(visual-studio-code spotify discord rectangle iterm2)
```

## What It Does

### System Settings
- Enables dark mode
- Sets dock to right orientation
- Enables single-app mode
- Configures 24-hour time format
- Sets date format to DD/MM/YYYY

### Development Setup
- Installs Homebrew (or updates if present)
- Configures Homebrew path for Apple Silicon
- Installs Rosetta 2 (Apple Silicon only)
- Downloads iTerm2 configuration from GitHub
- Installs Oh My Zsh

### Wallpapers
- Creates wallpaper directory
- Downloads images from S3 bucket
- Sets different wallpaper for each display
- Cycles through available images

## Debug Mode

Debug mode allows you to:
- See what the script would do without making changes
- Test AWS connectivity
- Verify application list
- Check system compatibility

## Troubleshooting

### AWS Issues
```bash
# Check AWS configuration
aws sts get-caller-identity

# Configure AWS if needed
aws configure
```

### Homebrew Issues
```bash
# Manually install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Update PATH for Apple Silicon
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

### iTerm2 Configuration
The script downloads iTerm2 settings from: 
`https://raw.githubusercontent.com/jamieal/iTerm-Config/refs/heads/main/com.googlecode.iterm2.plist`

## Security Notes

- Script checks against running as root
- Uses official Homebrew installation
- Downloads configurations from verified GitHub repos
- AWS credentials remain local

## Author

Jamie Cras - Version 1.1
