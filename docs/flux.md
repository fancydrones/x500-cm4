# Flux

Flux (v2) is a CD system to deploy new versions automatically. [More info can be found here.](https://fluxcd.io/)

## Upgrade flux

To install the newest version for flux cli, run the following command ([documentation](https://fluxcd.io/docs/installation/)):
    curl -s https://fluxcd.io/install.sh | sudo bash

## Upgrade Flux components

Run the following command to generate a new version of gotk-components.yaml:
    flux install --version=latest --export > gotk-component.yaml
