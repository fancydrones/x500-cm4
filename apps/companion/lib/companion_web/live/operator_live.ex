defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView

  require Logger

  def mount(_session, socket) do
    {:ok, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")
    token_file = Application.get_env(:companion, :token_file)
    {:ok, token} = File.read(token_file)
    Logger.info("Token: #{token}")
    #DroneAction.action(:gear_up_button)
    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")
    namespace_file = Application.get_env(:companion, :namespace_file)
    {:ok, namespace} = File.read(namespace_file)
    Logger.info("Namespace: #{namespace}")
    #DroneAction.action(:gear_down_button)
    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")
    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:6443/api/v1/namespaces/#{namespace}/configmaps/rpi4-config"
    Logger.info("URL: #{url}")
    headers = ["Authorization": "Bearer #{token}"]
    options = [ssl: [cacertfile: ca_file]]
    {:ok, response} = HTTPoison.get(url, headers, options)
    Logger.info("Status Code: #{response.status_code}")
    IO.inspect(response)
    200 = response.status_code
    {:ok, resp} = Jason.decode(response.body)
    ##Logger.info(resp["data"])
    IO.inspect(resp["data"])

    #DroneAction.action(:shutdown_button)
    {:noreply, socket}
  end

  def render(assigns) do
    ~L"""
    <div id="liveoperator_landinggear_container">
      <h1>Restart apps:</h1>
      <button phx-click="restart_router">Router</button>
      <button phx-click="restart_streamer">Streamer</button>
      <button phx-click="restart_announcer">Announcer</button>
    </div>
    """
  end
end
