# Button for shutting down (and starting again)
In any operating system not specifically preparred for this, a sudden power outage could damage the file system. An example of a power outage could be yanking the power plug (or disconnecting the battery on an UAV). In most cases no damage is done, and the file system is perfectly fine and good to go. But in that 1 out of 1000 time, when you really need the UAV to just boot up and go, the file system is damaged, and refuses to boot the OS.

To prevent this from happening, we simply use a button to shut down the OS gracefully. It turns out, that Raspberry Pi OS even has an overlay for just this. Simply connect a button between pin 5 (GPIO_3) and ground, introduce an overlay line to `/boot/config` and you are good to go.

Description based on the guide at [this link](https://www.stderr.nl/Blog/Hardware/RaspberryPi/PowerButton.html).

## Step by step
### Overlay
    sudo sh -c "echo 'dtoverlay=gpio-shutdown,gpio_pin=3' >> /boot/config.txt"

