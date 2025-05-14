# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.InstallTest do
  use ExUnit.Case, async: false

  import Igniter.Test

  alias Mix.Tasks.VintageNetWifi.Install

  doctest Install

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)

    on_exit(fn ->
      Mix.shell(shell)
    end)

    :ok
  end

  describe inspect(&Install.run/1) do
    test "sets up regulatory domain when provided as an argument" do
      assert {:ok, igniter, _} =
               test_project()
               |> Igniter.compose_task("vintage_net_wifi.install", ["--regulatory-domain", "US"])
               |> assert_creates("config/target.exs", """
               import Config
               config :vintage_net, regulatory_domain: "US", config: [{"wlan0", %{type: VintageNetWiFi}}]
               """)
               |> apply_igniter()

      igniter
      |> Igniter.compose_task("vintage_net_wifi.install", ["--regulatory-domain", "US"])
      |> assert_unchanged("config/target.exs")
    end

    test "prompts for regulatory domain" do
      send(self(), {:mix_shell_input, :prompt, "EU"})

      test_project()
      |> Igniter.compose_task("vintage_net_wifi.install", [])
      |> assert_creates("config/target.exs", """
      import Config
      config :vintage_net, regulatory_domain: "EU", config: [{"wlan0", %{type: VintageNetWiFi}}]
      """)
    end

    test "skips if interface with VintageNetWiFi already exists" do
      # send(self(), {:mix_shell_input, :prompt, "EU"})

      test_project(
        files: %{
          "config/target.exs" => """
          import Config

          config :vintage_net,
            regulatory_domain: "EU",
            config: [
              {"wlan0",
               %{
                 type: VintageNetWiFi,
                 ipv4: %{method: :dhcp}
               }}
            ]
          """
        }
      )
      |> Igniter.compose_task("vintage_net_wifi.install", [])
      |> assert_unchanged("config/target.exs")
    end

    test "appends if other interfaces already exists" do
      send(self(), {:mix_shell_input, :prompt, "EU"})

      test_project(
        files: %{
          "config/target.exs" => """
          import Config

          config :vintage_net,
            regulatory_domain: "EU",
            config: [{"eth0", %{type: VintageNetEthernet}}]
          """
        }
      )
      |> Igniter.compose_task("vintage_net_wifi.install", [])
      |> assert_has_patch("config/target.exs", """
         ...|
      3 3   |config :vintage_net,
      4 4   |  regulatory_domain: "EU",
      5   - |  config: [{"eth0", %{type: VintageNetEthernet}}]
        5 + |  config: [{"eth0", %{type: VintageNetEthernet}}, {"wlan0", %{type: VintageNetWiFi}}]
      """)
    end
  end
end
