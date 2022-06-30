FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y curl gnupg

RUN echo "deb http://archive.raspberrypi.org/debian/ bullseye main" > /etc/apt/sources.list.d/raspi.list
RUN curl "https://archive.raspberrypi.org/debian/raspberrypi.gpg.key" | apt-key add -

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y libcamera-dev

#RUN apt-get install libgstrtspserver-1.0-0 libgstreamer1.0-dev -y
RUN apt-get install libgstrtspserver-1.0-0 libgstreamer1.0-0 -y
RUN apt-get install libcairo2-dev libxt-dev libgirepository1.0-dev -y
#RUN apt-get install libcairo2 libxt-dev libgirepository1.0-dev -y
RUN apt-get install gir1.2-gst-rtsp-server-1.0 -y

RUN apt-get install python3 python3-pip -y

WORKDIR /src

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir --upgrade -r requirements.txt

COPY *.py ./

ENV UDEV=on

CMD ["python3", "main.py"]
