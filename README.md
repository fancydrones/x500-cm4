# RPiUAV
This repository aims at giving step by step instructs from zero to a fully operational UAV connected using a mobile phone and 4G/5G, by using available (ish) components and software. Some of the components selected are affected by the chip shortage (2022), and can be replaced as this hopefully improves going forward.

## Main components
- UAV from Holybro: X500 v2 ARF: [https://shop.holybro.com/x500-v2-kit_p1288.html](https://shop.holybro.com/x500-v2-kit_p1288.html)
- Pixhawk 6C (can be replaced if cheaper option comes available): 

## Details
- [Gimbal](gimbal/README.md)

## TODOs
- [x] Mavlink Router
- [x] Video Announcer
- [x] Servoes
- [ ] Document use of pan/tilt servoes
- [ ] Document 3D model for pant/tilt setup
- [x] k3s
- [ ] Smaller image for STREAMER, if possible
- [ ] Smaller image for ANNOUNCER, if possible
- [x] Build and store images in container registry
- [ ] fluxcd.io
- [ ] Document zerotier
- [ ] Document autoupdate OS
- [x] Consider if Raspberry Pi OS or Ubuntu. Raspberry PI OS for now. Will test out DietPi
- [ ] Step-by-step guide
- [ ] Document BOM (Bill of Materials)
- [ ] Document power-button
- [ ] Test (and document if successful) LED indicating running OS
- [ ] install.sh
- [ ] Document 6X network settings
- [ ] Document install OS



## Install
    curl -s https://gitlab.com/got.vision/rpiuav/-/raw/main/install.sh | sh -