defmodule CompanionWeb.OperatorLive do
  use Phoenix.LiveView

  require Logger

  def mount(_session, socket) do
    {:ok, socket}
  end

  def handle_event("set_config_system_id_222", _, socket) do
    Logger.info("Clicked Set System ID = 222")

    set_system_id("222")

    {:noreply, socket}
  end

  def handle_event("set_config_system_id_1", _, socket) do
    Logger.info("Clicked Set System ID = 1")

    set_system_id("1")

    {:noreply, socket}
  end

  def handle_event("get_config", _, socket) do
    Logger.info("Clicked restart Get Config")

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

  def handle_event("get_versions", _, socket) do
    Logger.info("Clicked restart Get Versions")

    #v_router = get_version("router")
    #IO.puts(v_router)


    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/apis/apps/v1/namespaces/#{namespace}/deployments"

    Logger.info("URL: #{url}")
    headers = ["Authorization": "Bearer #{token}"]
    options = [ssl: [cacertfile: ca_file]]
    {:ok, response} = HTTPoison.get(url, headers, options)
    Logger.info("Status Code: #{response.status_code}")
    200 = response.status_code
    {:ok, resp} = Jason.decode(response.body)
    #IO.inspect(resp)
    # containers = resp["spec"]["template"]["spec"]["containers"]
    # c = List.first(containers)
    # tag = c["image"]
    # [_image, version] = String.split(tag, ":")
    # IO.inspect(version)

    deployment = List.first(resp["items"])

    Enum.map(resp["items"], fn deployment -> IO.puts("#{get_name_from_deployment(deployment)} : #{get_image_version_from_deployment(deployment)}") end)

    {:noreply, socket}
  end

  def handle_event("restart_router", _, socket) do
    Logger.info("Clicked restart Router")

    restart_deployment("router")

    {:noreply, socket}
  end

  def handle_event("restart_streamer", _, socket) do
    Logger.info("Clicked restart Streamer")

    restart_deployment("streamer")

    {:noreply, socket}
  end

  def handle_event("restart_announcer", _, socket) do
    Logger.info("Clicked restart Announcer")

    restart_deployment("announcer")

    {:noreply, socket}
  end

  def handle_event("restart_companion", _, socket) do
    Logger.info("Clicked restart Companion")

    restart_deployment("companion")

    {:noreply, socket}
  end

  defp get_name_from_deployment(deployment) do
    deployment["metadata"]["name"]
  end

  defp get_image_version_from_deployment(deployment) do
    containers = deployment["spec"]["template"]["spec"]["containers"]
    c = List.first(containers)
    tag = c["image"]
    [_image, version] = String.split(tag, ":")
    version
  end

  defp set_system_id(system_id) do
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

    b =
      %{
        data: %{
          "ANNOUNCER_SYSTEM_ID": system_id
        }
      }
    body = Jason.encode!(b)
    {:ok, response} = HTTPoison.patch(url, body, headers, options)

    IO.inspect(response)
    200 = response.status_code
  end

  defp restart_deployment(deployment_name) do
    namespace_file = Application.get_env(:companion, :namespace_file)
    token_file = Application.get_env(:companion, :token_file)
    ca_file = Application.get_env(:companion, :root_ca_certificate_file)
    kube_server = Application.get_env(:companion, :kubernetes_server)
    kube_server_port = Application.get_env(:companion, :kubernetes_server_port)

    {:ok, token} = File.read(token_file)
    token = token |> String.trim
    {:ok, namespace} = File.read(namespace_file)
    namespace = namespace |> String.trim

    url = "https://#{kube_server}:#{kube_server_port}/apis/apps/v1/namespaces/#{namespace}/deployments/#{deployment_name}?fieldManager=rpi-modifier"
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

    IO.inspect(response)
    200 = response.status_code
  end

  def render(assigns) do
    ~L"""
    <div id="liveoperator_landinggear_container">
      <h1>Update Config:</h1>
      <button phx-click="set_config_system_id_222">System ID = 222</button>
      <button phx-click="set_config_system_id_1">System ID = 1</button>
      <button phx-click="get_config">Get All Config</button>
      <button phx-click="get_versions">Get Image Versions
    </div>

    <div id="liveoperator_landinggear_container">
      <h1>Restart apps:</h1>
      <button phx-click="restart_router">Router</button>
      <button phx-click="restart_streamer">Streamer</button>
      <button phx-click="restart_announcer">Announcer</button>
      <button phx-click="restart_companion">Companion</button>
    </div>
    """
  end
end
