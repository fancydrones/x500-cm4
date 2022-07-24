# Companion

Supporting web service to configure UAV setup

## New project
    mix phx.new companion --no-ecto --no-mailer --app companion --module Companion

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

# Notes
Token file: /var/run/secrets/kubernetes.io/serviceaccount/token
Namespace file: /var/run/secrets/kubernetes.io/serviceaccount/namespace
URL: https://${KUBERNETES_PORT_443_TCP_ADDR}/api/v1/namespaces

# Work In Porgress
## CA file
    /var/lib/rancher/k3s/server/tls/server-ca.crt

## TEST
    token = "xxxx"
    url = "https://10.10.10.2:6443/api/v1/namespaces/rpiuav/configmaps/rpi4-config"
    headers = ["Authorization": "Bearer #{token}"]
    options = [ssl: [cacertfile: "/home/roy/ca.crt"]]
    {:ok, response} = HTTPoison.get(url, headers, options)
    {:ok, resp} = Jason.decode(response.body)
    resp["data"]

### Patch ConfigMap
    token = "xxxx"
    url = "https://10.10.10.2:6443/api/v1/namespaces/rpiuav/configmaps/rpi4-config?fieldManager=rpi-modifier"
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/strategic-merge-patch+json"]
    options = [ssl: [cacertfile: "/home/roy/ca.crt"]]
    body = "{\"data\":{\"ANNOUNCER_SYSTEM_ID\":\"12345\"}}"
    {:ok, response} = HTTPoison.patch(url, body, headers, options)

### Restart deployment
    token = "xxxx"
    url = "https://10.10.10.2:6443/apis/apps/v1/namespaces/rpiuav/deployments/router?fieldManager=rpi-modifier"
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/strategic-merge-patch+json"]
    options = [ssl: [cacertfile: "/home/roy/ca.crt"]]
    body = "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"2022-07-16T15:46:00+02:00\"}}}}}"
    {:ok, response} = HTTPoison.patch(url, body, headers, options)

## Concepts
ClusterRole - set on permissions
ServiceAccount - account that can be attached to a deployment
ClusterRoleBinding - connecting servceiAccount and ClusterRole


## To Edit

    kubectl patch configmap/rpi4-config -n rpiuav -p '{"data":{"ANNOUNCER_SYSTEM_ID":"1"}}'

    KUBE_API=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
    JWT_TOKEN=$(kubectl -n rpiuav create token rpimodifier)
    curl $KUBE_API/api/v1/namespaces/rpiuav/configmaps/rpi4-config -k -H "Authorization: Bearer $JWT_TOKEN"
    curl -X PATCH "$KUBE_API/api/v1/namespaces/rpiuav/configmaps/rpi4-config?fieldManager=rpi-modifier" -k -H "Authorization: Bearer $JWT_TOKEN" -H "Content-Type: application/strategic-merge-patch+json" -d '{"data":{"ANNOUNCER_SYSTEM_ID":"1234"}}'


## To restart
    curl -X PATCH "$KUBE_API/apis/apps/v1/namespaces/rpiuav/deployments/router?fieldManager=rpi-modifier" -k -H "Authorization: Bearer $JWT_TOKEN" -H "Content-Type: application/strategic-merge-patch+json" -d '{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"2022-07-16T15:05:00+02:00"}}}}}'