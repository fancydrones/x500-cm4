# Add to config.txt
    # Custom for RPiUAV
    gpu_mem=256
    enable_uart=1
    dtoverlay=gpio-shutdown,gpio_pin=3
    dtoverlay=gpio-led,gpio=17,trigger=default-on,label=statusled0
    camera_auto_detect=1