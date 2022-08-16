#!/bin/bash
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-rpi4/main/deployments/apps/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-rpi4/main/config/rpi4-configmap.yaml
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-rpi4/main/deployments/flux-system/gotk-components.yaml
flux create source git flux-infra --url=https://github.com/fancydrones/x500-rpi4 --branch=main --interval=1m
flux create kustomization rpi4 --source=flux-infra --path="./deployments" --prune=true --interval=5m