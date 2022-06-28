FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade -y

RUN apt-get install libx264-dev libjpeg-dev -y
RUN apt-get install libgstreamer1.0-dev \
     libgstreamer-plugins-base1.0-dev \
     libgstreamer-plugins-bad1.0-dev \
     gstreamer1.0-plugins-ugly \
     gstreamer1.0-tools \
     gstreamer1.0-gl \
     gstreamer1.0-gtk3 -y

RUN apt-get install libgstrtspserver-1.0-0 libgstreamer1.0-dev -y
RUN apt-get install libcairo2-dev libxt-dev libgirepository1.0-dev -y
RUN apt-get install gir1.2-gst-rtsp-server-1.0 -y

RUN apt-get install libcamera-dev \
    libcamera-apps-lite \
    python3 \
    v4l-utils -y

RUN apt-get install python3-pip -y

WORKDIR /src

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir --upgrade -r requirements.txt

COPY *.py ./

ENV UDEV=on

CMD ["python3", "main.py"]
