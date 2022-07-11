#!/bin/bash
# TODO: Check if need to elevate
# TODO: Make idempotent (possible to run multiple times)

# Update + upgrade
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade

 cgroups
# Need to append the lines to allow K3S to work properly
sudo sed -i '$s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt

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

# Set static IP for wired ethernet
echo "auto eth0" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null
echo "iface eth0 inet static" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null
echo "  address 10.9.8.1" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null
echo "  netmask 255.255.255.0" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null
echo "  gateway 10.9.8.1" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null
echo "  dns-nameservers 1.1.1.1" | sudo tee -a /etc/network/interfaces.d/eth0 > /dev/null

# Automatic updates
sudo apt-get install unattended-upgrades -y
sudo dpkg-reconfigure --priority=medium unattended-upgrades

# Flux
curl -s https://fluxcd.io/install.sh | sudo bash

# Update + upgrade
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt -y upgrade