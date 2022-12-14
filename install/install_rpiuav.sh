#!/bin/bash
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-cm4/main/deployments/apps/rpiuav-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-cm4/main/config/rpi4-configmap.yaml
kubectl apply -f https://raw.githubusercontent.com/fancydrones/x500-cm4/main/deployments/flux-system/gotk-components.yaml
flux create source git flux-infra --url=https://github.com/fancydrones/x500-cm4 --branch=main --interval=1m
flux create kustomization rpi4 --source=flux-infra --path="./deployments" --prune=true --interval=5m