# Config
## Edit configmap
    kubectl edit configmap rpi4-config -n rpiuav

## Restart deployment
    kubectl rollout restart deploy router -n rpiuav