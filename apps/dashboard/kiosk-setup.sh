#!/bin/bash

# Kiosk Mode Setup for Raspberry Pi or Linux with 1024x600 touchscreen
# This script configures the system to auto-start the dashboard in kiosk mode

echo "Setting up kiosk mode for dashboard..."

# Install required packages
sudo apt-get update
sudo apt-get install -y chromium-browser xserver-xorg xinit unclutter

# Create kiosk script
cat > ~/start-dashboard-kiosk.sh << 'EOF'
#!/bin/bash

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor after 1 second of inactivity
unclutter -idle 1 &

# Start Chromium in kiosk mode
chromium-browser \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=TranslateUI \
  --check-for-update-interval=604800 \
  --window-size=1024,600 \
  --window-position=0,0 \
  --start-fullscreen \
  --incognito \
  http://localhost:30080
EOF

chmod +x ~/start-dashboard-kiosk.sh

# Create systemd service for auto-start
sudo tee /etc/systemd/system/dashboard-kiosk.service << 'EOF'
[Unit]
Description=Dashboard Kiosk Mode
After=graphical.target

[Service]
Type=simple
User=pi
Environment="DISPLAY=:0"
ExecStart=/home/pi/start-dashboard-kiosk.sh
Restart=always
RestartSec=10

[Install]
WantedBy=graphical.target
EOF

# Enable the service
sudo systemctl daemon-reload
sudo systemctl enable dashboard-kiosk.service

# Configure auto-login (for Raspberry Pi OS)
sudo raspi-config nonint do_boot_behaviour B4

echo "✅ Kiosk mode setup complete!"
echo "The dashboard will start automatically on boot in fullscreen kiosk mode."
echo "To start manually: ~/start-dashboard-kiosk.sh"