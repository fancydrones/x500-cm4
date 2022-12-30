# To build locally using buildx and docker run the following commands:

- docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
- docker buildx create --use
- docker buildx build --platform linux/aarch64 .
