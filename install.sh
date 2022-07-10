#!/bin/bash
# TODO: Check if need to elevate

# Update + upgrade
sudo apt-get update && sudo apt-get upgrade -y

# Docker
#curl -sSL https://get.docker.com | sh

# K3S
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

# Overlays
sudo sh -c "echo 'gpu_mem=256' >> /boot/config.txt"
sudo sh -c "echo 'enable_uart=1' >> /boot/config.txt"
sudo sh -c "echo 'dtoverlay=gpio-shutdown,gpio_pin=3' >> /boot/config.txt"
sudo sh -c "echo 'dtoverlay=gpio-led,gpio=17,trigger=default-on,label=statusled0' >> /boot/config.txt"

# Zerotier
curl -s https://install.zerotier.com | sudo bash

# cgroups
# Need to append the lines to allow K3S to work properly
sudo sed -i '$s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt

# Update + upgrade
sudo apt-get update && sudo apt-get upgrade -y