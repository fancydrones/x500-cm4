FROM python:3-alpine

WORKDIR /src

COPY requirements.txt requirements.txt
ARG DISABLE_MAVNATIVE=1 # Disable native build of pymavlink, since it is only for mavlink1 anyway

#RUN apt-get install libxml2-dev libxslt-dev python3-dev
#RUN apk update && apk add --no-cache gcc  python3-dev && rm -rf /var/cache/apk/*

RUN apk update && apk add --no-cache gcc \
        g++ \
        git \
        pkgconf \
        meson \
        ninja \
        linux-headers \
        libxml2-dev \
        libxslt-dev \
        &&  rm -rf /var/cache/apk/*

RUN pip install --upgrade pip
RUN pip install --no-cache-dir --upgrade -r requirements.txt

COPY *.py ./

ENV MAVLINK20=1
CMD ["python3", "main.py"]
