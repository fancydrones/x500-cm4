FROM python:3-alpine

LABEL "author"="Roy Veshovda"
LABEL "company"="Fancy Drones"
LABEL org.opencontainers.image.description Fancy Drones X500-RPi4 Announcer

WORKDIR /src

COPY requirements.txt requirements.txt
ARG DISABLE_MAVNATIVE=1 # Disable native build of pymavlink, since it is only for mavlink1 anyway

RUN pip install --no-cache-dir --upgrade -r requirements.txt

COPY *.py ./

ENV MAVLINK20=1
CMD ["python3", "main.py"]
