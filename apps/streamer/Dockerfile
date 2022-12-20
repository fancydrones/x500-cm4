FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y curl gnupg

RUN echo "deb http://archive.raspberrypi.org/debian/ bullseye main" > /etc/apt/sources.list.d/raspi.list
RUN curl "https://archive.raspberrypi.org/debian/raspberrypi.gpg.key" | apt-key add -

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y libcamera-dev libcamera-apps

# RUN apt-get install -y git
# RUN apt-get install -y meson
# RUN apt-get install -y g++
# RUN apt-get install -y cmake
# RUN apt-get install -y libxml2-dev libxslt-dev python3-dev
# RUN apt-get install -y libyaml-dev python3-yaml python3-ply python3-jinja2

# RUN apt-get install -y libdw-dev libunwind-dev

# RUN apt-get install -y libudev-dev
# RUN apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
# RUN apt-get install -y libevent-dev libdrm-dev libjpeg-dev libsdl2-dev

# RUN git clone https://git.libcamera.org/libcamera/libcamera.git
# WORKDIR /libcamera
# RUN meson build
# RUN ninja -C build install

RUN apt-get install libgstrtspserver-1.0-0 libgstreamer1.0-0 -y
RUN apt-get install libcairo2-dev libxt-dev libgirepository1.0-dev -y
RUN apt-get install gir1.2-gst-rtsp-server-1.0 -y

RUN apt-get install python3 python3-pip -y

WORKDIR /src

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir --upgrade -r requirements.txt

COPY *.py ./

CMD ["python3", "main.py"]
