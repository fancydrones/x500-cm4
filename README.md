# RPiUAV
This repository aims at giving step by step instructs from zero to a fully operational UAV connected using a mobile phone and 4G/5G, by using available (ish) components and software. Some of the components selected are affected by the chip shortage (2022), and can be replaced as this hopefully improves going forward.

Documentation can be found at [https://fancydrones.github.io/x500-rpi4](https://fancydrones.github.io/x500-rpi4)


## TODOs
- [ ] Update Streamer to support AMD64 aarch
- [x] Scope workflows to updates in relevant paths only
- [x] Publish documentation using Github Pages
- [x] Move documentation to use Github Pages (/docs)
- [ ] Document use of pan/tilt servoes
- [ ] Document 3D model for pant/tilt setup
- [ ] Document hardware installation
- [ ] Document high level concept
- [ ] Consider k3s hardening ([https://rancher.com/docs/k3s/latest/en/security/hardening_guide/](https://rancher.com/docs/k3s/latest/en/security/hardening_guide/))
- [ ] Try to avoid network=host for Router (see Nodeport range below)
- [ ] Try to avoid network=host for Streamer (see Nodeport range below)
- [ ] Try to avoid "priviledged=true" for Streamer (must grant access to camera)
- [ ] Try to avoid "priviledged=true" for Router (must grant access to serial port)
- [ ] (Nice to have) Consider moving Announcer to Companion
- [ ] (Nice to have) Improve Companion by connecting to Mavlink
- [ ] (Nice to have) Show Autopilot Status on Companion
- [ ] (Nice to have) Show Autopilot position on Companion
- [ ] (Nice to have) Set important paramaters on Autopilot using Companion over Mavlink
- [ ] Update docker-compose to be able to develop locally
- ~~[ ] Enable Origin check for Companion~~ (not needed for now. Will only complicate setups)
- ~~[ ] Smaller image for STREAMER, if possible~~ (GStreamer+Python will increase size)

### [ ] TODO: Extend range for allowed port for NodePort
Default NodePort will only allow ports between 30000 and 32767. This could work, but will cause some non-standard port to be used for services, and might cause problems down stream.

Fix is to extend allowed port range for NodePort, and this will be done during installation of k3s. Must add the following 
    --service-node-port-range “1000-32767”

Or use config file for installation: [https://rancher.com/docs/k3s/latest/en/installation/install-options/#configuration-file](https://rancher.com/docs/k3s/latest/en/installation/install-options/#configuration-file)
