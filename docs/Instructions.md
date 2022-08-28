# Pinout:
https://pinout.xyz/#

## UART:
RPI - TX: 8 <--> 3 RX - Tel1
RPI - RX: 10 <--> 2 TX - Tel1
RPI - GND: 14 <--> 6 TX - Tel1

## Shutdown button
Connect [GND](https://pinout.xyz/pinout/ground#) and [GPIO 3](https://pinout.xyz/pinout/pin5_gpio3#) between a button. Final step is to add `dtoverlay=gpio-shutdown,gpio_pin=3` to the end of the file `/boot/config.txt` (install.sh will do this for you). A quick reboot later, and you can shut doen the OS by clicking the button. Mark that the RPi will not power down, and hence, still consume a bit of power. But the OS will be cleanly shut down, to prevent currupted files. This in combination with a status LED will make sure your RPi will operate for a long time.

## Staus LED
Connect the short leg of the LED to an resistor of about 480OHM, and the other side of the resistor to [GND](https://pinout.xyz/pinout/ground#). The long leg of the LED you connect to [GPIO 17](https://pinout.xyz/pinout/pin11_gpio17#). Also add `dtoverlay=gpio-led,gpio=17,trigger=default-on,label=statusled0` to the end of the file `/boot/config.txt` (install.sh will do this for you). Reboot, and you will have en external LED, that can be much easier for the operator to see than the fixed on RPi.