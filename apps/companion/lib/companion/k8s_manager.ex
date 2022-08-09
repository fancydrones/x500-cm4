defmodule Companion.K8sManager do
  def get_api_manager() do
    Application.get_env(:companion, :k8s_api_manager)
  end

  def update_config(key, value) do
    get_api_manager().update_config(key, value)
  end

  def restart_deployment(deployment_name) do
    get_api_manager().restart_deployment(deployment_name)
  end

  def request_deployments() do
    get_api_manager().request_deployments()
  end

  def request_configs() do
    get_api_manager().request_configs()
  end


end
