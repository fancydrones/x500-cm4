#!/bin/bash
kubectl apply -f https://gitlab.com/got.vision/rpiuav/-/raw/main/deployments/rpi4/flux-system/gotk-components.yaml?inline=false
flux create source git flux-infra --url=https://gitlab.com/got.vision/rpiuav --branch=main --interval=1m
flux create kustomization rpi4 --source=flux-infra --path="./deployments/rpi4" --prune=true --interval=5m