defmodule VintageNet.Technology.WiFi do
  @behaviour VintageNet.Technology

  @moduledoc """
  Deprecated - Use VintageNetWiFi now

  This module will automatically redirect your configurations to VintageNetWiFi so
  no changes are needed to your code. New code should use the new module.
  """
  @impl true
  def normalize(%{type: __MODULE__} = config) do
    config
    |> update_config()
    |> VintageNetWiFi.normalize()
  end

  @impl true
  def to_raw_config(ifname, config, opts) do
    updated_config = update_config(config)
    VintageNetWiFi.to_raw_config(ifname, updated_config, opts)
  end

  defp update_config(%{wifi: wifi} = config) do
    config
    |> Map.drop([:wifi])
    |> Map.put(:type, VintageNetWiFi)
    |> Map.put(:vintage_net_wifi, wifi)
  end

  defp update_config(config) do
    config
    |> Map.put(:type, VintageNetWiFi)
  end

  defdelegate ioctl(ifname, command, args), to: VintageNetWiFi

  defdelegate check_system(opts), to: VintageNetWiFi
end
