#!/bin/bash

# Set the log file name and path
LOG_FILE="/tmp/system_diagnosis.log"

# Create the log file and set the permissions
echo "System Diagnosis Log" > $LOG_FILE
chmod 644 $LOG_FILE

# Gather system information
echo "System Information:" >> $LOG_FILE
echo "------------------" >> $LOG_FILE
uname -a >> $LOG_FILE
free -h >> $LOG_FILE
df -h >> $LOG_FILE
lsblk >> $LOG_FILE

# Check for large files
echo "Large Files:" >> $LOG_FILE
echo "------------" >> $LOG_FILE
find / -type f -size +100M >> $LOG_FILE

# Check for running processes
echo "Running Processes:" >> $LOG_FILE
echo "-----------------" >> $LOG_FILE
ps aux >> $LOG_FILE

# Check for network activity
echo "Network Activity:" >> $LOG_FILE
echo "-----------------" >> $LOG_FILE
netstat -tlnp >> $LOG_FILE
ss -tlnp >> $LOG_FILE

# Check for system logs
echo "System Logs:" >> $LOG_FILE
echo "------------" >> $LOG_FILE
journalctl -u systemd-journald >> $LOG_FILE
journalctl -u rsyslogd >> $LOG_FILE

# Check for disk usage
echo "Disk Usage:" >> $LOG_FILE
echo "------------" >> $LOG_FILE
du -h / >> $LOG_FILE

# Check for system configuration files
echo "System Configuration Files:" >> $LOG_FILE
echo "---------------------------" >> $LOG_FILE
find /etc -type f >> $LOG_FILE

# Print the log file
echo "System Diagnosis Log saved to $LOG_FILE"
cat $LOG_FILE
