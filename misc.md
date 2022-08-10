# Other usefull notes
## Cleanup disk space
While k3s will clean up unused images above a threshold (90% full disk), it might be usefull to prune unused images to free up the space manually. This is especially true dusring development, when changes are rapid. Commands to clean in K3s are the following:
- `sudo k3s crictl images` to see what images have been pulled locally
- `sudo k3s crictl rmi --prune` to delete any images not currently used by any running container 