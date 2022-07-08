#!/bin/bash
# TODO: Check if need to elevate

# Update + upgrade
sudo apt-get update && sudo apt-get upgrade

# Docker
#curl -sSL https://get.docker.com | sh

# K3S
curl -sfL https://get.k3s.io | sh -

# Overlays
sudo sh -c "echo 'gpu_mem=256' >> /boot/config.txt"
sudo sh -c "echo 'enable_uart=1' >> /boot/config.txt"
sudo sh -c "echo 'dtoverlay=gpio-shutdown,gpio_pin=3' >> /boot/config.txt"

# Zerotier
curl -s https://install.zerotier.com | sudo bash