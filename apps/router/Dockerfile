# Build stage
FROM alpine:3 AS builder

WORKDIR /mavlink-router

RUN apk update && apk add --no-cache gcc \
        g++ \
        git \
        pkgconf \
        meson \
        ninja \
        linux-headers \
        &&  rm -rf /var/cache/apk/*

RUN git clone https://github.com/mavlink-router/mavlink-router.git /mavlink-router

RUN git submodule update --init --recursive
RUN meson setup -Dsystemdsystemunitdir=/usr/lib/systemd/system --buildtype=release build . 
RUN ninja -C build

# Run stage
FROM alpine:3
WORKDIR /mavlink-router
RUN apk update && apk upgrade && apk add --no-cache libstdc++

# # Copy binary from builder
COPY --from=builder /mavlink-router/build/src/mavlink-routerd .
ENTRYPOINT ["/mavlink-router/mavlink-routerd"]
