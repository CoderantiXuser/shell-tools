#!/bin/bash

#mystartup.sh
xset b 10 10 10


# Create the service file
cat <<EOF | sudo tee /etc/systemd/system/startup_commands.service
[Unit]
Description=Run startup commands
After=network.target bluetooth.target

[Service]
ExecStart=/bin/bash -c 'sudo systemctl start bluetooth && blueman-manager & cd ~/Development/Pythonn/piperui && python main.sh'
Type=oneshot
RemainAfterExit=yes
User=$USER

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable startup_commands.service