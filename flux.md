# Configure Flux
## Init
Create the initial flux-file using this command:
    flux install --version=latest --export > gotk-component.yaml
    kubectl apply -f gotk-component.yaml



    flux bootstrap gitlab --owner=got.vision --repository=rpiuav --path=deployments/rpi4 --reconsile



flux create source git flux-infra   --url=https://gitlab.com/got.vision/rpiuav   --interval=1m --branch=main
