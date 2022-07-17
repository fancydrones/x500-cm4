defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView

  require Logger

  def mount(_session, socket) do
    {:ok, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")

    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/api/v1/namespaces/#{namespace}/configmaps/rpi4-config?fieldManager=rpi-modifier"
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/strategic-merge-patch+json"]
    options = [ssl: [cacertfile: ca_file]]
    body = "{\"data\":{\"ANNOUNCER_SYSTEM_ID\":\"123456\"}}"
    {:ok, response} = HTTPoison.patch(url, body, headers, options)

    IO.inspect(response)
    200 = response.status_code

    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")
    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/api/v1/namespaces/#{namespace}/configmaps/rpi4-config?fieldManager=rpi-modifier"
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/strategic-merge-patch+json"]
    options = [ssl: [cacertfile: ca_file]]
    body = "{\"data\":{\"ANNOUNCER_SYSTEM_ID\":\"1\"}}"
    {:ok, response} = HTTPoison.patch(url, body, headers, options)

    IO.inspect(response)
    200 = response.status_code

    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")

    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/api/v1/namespaces/#{namespace}/configmaps/rpi4-config"
    Logger.info("URL: #{url}")
    headers = ["Authorization": "Bearer #{token}"]
    options = [ssl: [cacertfile: ca_file]]
    {:ok, response} = HTTPoison.get(url, headers, options)
    Logger.info("Status Code: #{response.status_code}")
    IO.inspect(response)
    200 = response.status_code
    {:ok, resp} = Jason.decode(response.body)
    IO.inspect(resp["data"])

    #DroneAction.action(:shutdown_button)
    {:noreply, socket}
  end

  def handle_event("restart_temp", _, socket) do
    Logger.info("Clicked restart Temp")

    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/apis/apps/v1/namespaces/rpiuav/deployments/mavision-router?fieldManager=rpi-modifier"
    Logger.info("URL: #{url}")
    headers = ["Authorization": "Bearer #{token}", "Content-Type": "application/strategic-merge-patch+json"]
    options = [ssl: [cacertfile: ca_file]]


    b =
      %{
        spec: %{
          template: %{
            metadata: %{
              annotations: %{
                "kubectl.kubernetes.io/restartedAt": DateTime.utc_now |> DateTime.to_iso8601
              }
            }
          }
        }
      }
    body = Jason.encode!(b)

    {:ok, response} = HTTPoison.patch(url, body, headers, options)

    # TODO

    {:noreply, socket}
  end


  def render(assigns) do
    ~L"""
    <div id="liveoperator_landinggear_container">
      <h1>Restart apps:</h1>
      <button phx-click="restart_router">Router (System ID = 123456)</button>
      <button phx-click="restart_streamer">Streamer (System ID = 1)</button>
      <button phx-click="restart_announcer">Announcer (Get All Config)</button>
      <button phx-click="restart_temp">TEMP (Restart Router)</button>
    </div>
    """
  end
end
