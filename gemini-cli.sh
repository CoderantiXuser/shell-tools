#!/bin/bash

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Installing Node.js..."
    # For Ubuntu/Debian
    sudo apt update && sudo apt install -y nodejs npm || {
        echo "Failed to install Node.js. Trying alternative method..."
        curl -fsSL https://deb.nodesource.com/setup_23.x | sudo -E bash -
        sudo apt-get install -y nodejs
    }
fi

# Install/Update Gemini CLI globally
echo "Setting up Gemini CLI..."
npm install -g @google/gemini-cli || {
    echo "Fallback to direct GitHub install"
    npm install -g https://github.com/google-gemini/gemini-cli
}

# Configure autostart
cat <<EOF > ~/.gemini_autostart.sh
#!/bin/bash
# Wait for network connection
until ping -c1 google.com &>/dev/null; do sleep 1; done

# Launch Gemini CLI with auth check
if ! gemini --check-auth &>/dev/null; then
    echo "Authenticating Gemini CLI..."
    gemini --auth --theme=dark --login-method=google
fi

# Start interactive session
gemini --chat
EOF

chmod +x ~/.gemini_autostart.sh

# Add to startup (multiple methods)
## Method 1: systemd (headless servers)
if [ -d /etc/systemd/system ]; then
    cat <<EOF | sudo tee /etc/systemd/system/gemini-cli.service
[Unit]
Description=Gemini CLI Autostart
After=network.target

[Service]
ExecStart=$HOME/.gemini_autostart.sh
Restart=on-failure
User=$USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=$HOME/.Xauthority"

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable gemini-cli.service
fi

## Method 2: Desktop autostart (GUI environments)
if [ -d ~/.config/autostart ]; then
    cat <<EOF > ~/.config/autostart/gemini-cli.desktop
[Desktop Entry]
Type=Application
Name=Gemini CLI
Exec=$HOME/.gemini_autostart.sh
Terminal=true
EOF
fi

echo "Gemini CLI setup complete! It will auto-start on next login."