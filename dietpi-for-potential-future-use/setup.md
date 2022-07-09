# Setup using DietPi
- Download image
- burn image
- Update: `dietpi.txt` with contecnt from here
- Update `dietpi-wifi.txt` with WiFi details (`aWIFI_SSID[0]` and `aWIFI_KEY[0]`)
- Append to config.txt from here
- add ` cgroup_enable=memory cgroup_memory=1` to `/boot/cmdline.txt`
- copy eth0 to `/etc/network/interfaces.d/` to set static IP to wired ethernet
- copy usb0 to `/etc/network/interfaces.d/` to enable usb modem




## To get camera to work
- dtoverlay=rpivid-v4l2