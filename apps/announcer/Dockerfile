FROM python:3-alpine as pythonBuilder

WORKDIR /src

COPY requirements-1.txt requirements-1.txt
ARG DISABLE_MAVNATIVE=1 # Disable native build of pymavlink, since it is only for mavlink1 anyway

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
RUN pip install --no-cache-dir --upgrade --target=/src/dependencies -r requirements-1.txt

FROM python:3-alpine
WORKDIR /src
COPY *.py ./
COPY requirements-2.txt requirements-2.txt
COPY --from=pythonBuilder /src .
ENV PYTHONPATH="${PYTHONPATH}:/src/dependencies"
RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir --upgrade -r requirements-2.txt

ENV MAVLINK20=1
CMD ["python3", "main.py"]
