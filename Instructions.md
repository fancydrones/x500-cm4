Download image from:
git@gitlab.com:got.vision/rpiuav.git

# Pinout:
https://pinout.xyz/#


## UART:
RPI - TX: 8 <--> 3 RX - Tel1
RPI - RX: 10 <--> 2 TX - Tel1
RPI - GND: 14 <--> 6 TX - Tel1

# Install
Follow the steps below to get up and running

## Install Docker
    curl -sSL https://get.docker.com | sh
    sudo apt-get install -y uidmap

## Install repo
    sudo apt install git -y

    git clone https://gitlab.com/got.vision/rpiuav
    cd rpiuav
    sudo docker compose build

## Packages
    sudo apt-get install libx264-dev libjpeg-dev
    sudo apt-get install libgstreamer1.0-dev \
     libgstreamer-plugins-base1.0-dev \
     libgstreamer-plugins-bad1.0-dev \
     gstreamer1.0-plugins-ugly \
     gstreamer1.0-tools \
     gstreamer1.0-gl \
     gstreamer1.0-gtk3

    sudo apt install libgstrtspserver-1.0-0 libgstreamer1.0-dev -y
    sudo apt install python3-pip -y
    sudo apt install libcairo2-dev libxt-dev libgirepository1.0-dev
    pip3 install PyGObject, pycairo
    pip install typing
    sudo apt install gir1.2-gst-rtsp-server-1.0
    curl -s https://install.zerotier.com | sudo bash

## Enable serial0 (ttyS0)
    sudo raspi-config nonint do_serial 2 # disable serial console, but enable serial hardware (/dev/serial0)

export CAMERA_PIPELINE0='libcamerasrc ! video/x-raw,width=1280,height=720,format=NV12,colorimetry=bt601,interlace-mode=progressive ! videoflip video-direction=identity ! videorate ! video/x-raw,framerate=30/1 ! v4l2convert ! v4l2h264enc output-io-mode=2 extra-controls="controls,repeat_sequence_header=1,video_bitrate_mode=1,h264_profile=3,video_bitrate=5000000" ! video/x-h264,profile=main,level=(string)4 ! queue max-size-buffers=1 name=q_enc ! h264parse ! rtph264pay config-interval=1 name=pay0 pt=96'

