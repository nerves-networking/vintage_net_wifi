# SPDX-FileCopyrightText: 2025 Jonatan Männchen <jonatan@maennchen.ch>
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule Mix.Tasks.VintageNetWifi.AddNetworktest do
  use ExUnit.Case, async: true

  import Igniter.Test

  alias Mix.Tasks.VintageNetWifi.AddNetwork

  doctest AddNetwork

  describe inspect(&AddNetwork.run/1) do
    test "adds network to existing interface" do
      test_project(
        files: %{
          "config/target.exs" => """
          import Config

          config :vintage_net,
            regulatory_domain: "EU",
            config: [{"wlan0", %{type: VintageNetWiFi}}]
          """
        }
      )
      |> Igniter.compose_task("vintage_net_wifi.add_network", [
        "wlan0",
        "--ssid",
        "MySSID",
        "--key-mgmt",
        "wpa_psk",
        "--psk",
        "MySecretPassword"
      ])
      # TODO: Fix Map Keys (atom: instead of :atom =>)
      |> assert_has_patch("config/target.exs", """
          ...|
      3  3   |config :vintage_net,
      4  4   |  regulatory_domain: "EU",
      5    - |  config: [{"wlan0", %{type: VintageNetWiFi}}]
         5 + |  config: [
         6 + |    {"wlan0",
         7 + |     %{
         8 + |       :type => VintageNetWiFi,
         9 + |       :networks => [%{key_mgmt: :wpa_psk, psk: "MySecretPassword", ssid: "MySSID"}]
        10 + |     }}
        11 + |  ]
      """)
    end

    test "adds network to existing interface with other networks" do
      test_project(
        files: %{
          "config/target.exs" => """
          import Config

          config :vintage_net,
            regulatory_domain: "EU",
            config: [{"wlan0", %{type: VintageNetWiFi, networks: [%{key_mgmt: :none, ssid: "test"}]}}]
          """
        }
      )
      |> Igniter.compose_task("vintage_net_wifi.add_network", [
        "wlan0",
        "--ssid",
        "MySSID",
        "--key-mgmt",
        "wpa_psk",
        "--psk",
        "MySecretPassword"
      ])
      |> assert_has_patch("config/target.exs", """
          ...|
      3  3   |config :vintage_net,
      4  4   |  regulatory_domain: "EU",
      5    - |  config: [{"wlan0", %{type: VintageNetWiFi, networks: [%{key_mgmt: :none, ssid: "test"}]}}]
         5 + |  config: [
         6 + |    {"wlan0",
         7 + |     %{
         8 + |       type: VintageNetWiFi,
         9 + |       networks: [
        10 + |         %{key_mgmt: :none, ssid: "test"},
        11 + |         %{key_mgmt: :wpa_psk, psk: "MySecretPassword", ssid: "MySSID"}
        12 + |       ]
        13 + |     }}
        14 + |  ]
      """)
    end

    test "calls install if no interfaces are installed" do
      test_project()
      |> Igniter.compose_task("vintage_net_wifi.add_network", [
        "wlan0",
        "--ssid",
        "MySSID",
        "--key-mgmt",
        "wpa_psk",
        "--psk",
        "MySecretPassword",
        "--regulatory-domain",
        "00"
      ])
      |> assert_creates("config/target.exs", """
      import Config

      config :vintage_net,
        regulatory_domain: "00",
        config: [
          {"wlan0",
           %{
             type: VintageNetWiFi,
             networks: [%{key_mgmt: :wpa_psk, psk: "MySecretPassword", ssid: "MySSID"}]
           }}
        ]
      """)
    end

    test "sets up new interface if it does not already exist" do
      test_project()
      |> Igniter.compose_task("vintage_net_wifi.add_network", [
        "wlanname",
        "--ssid",
        "MySSID",
        "--key-mgmt",
        "wpa_psk",
        "--psk",
        "MySecretPassword",
        "--regulatory-domain",
        "00"
      ])
      # TODO: Fix Map Keys (atom: instead of :atom =>)
      |> assert_creates("config/target.exs", """
      import Config

      config :vintage_net,
        regulatory_domain: "00",
        config: [
          {"wlanname",
           %{
             type: VintageNetWiFi,
             networks: [%{key_mgmt: :wpa_psk, psk: "MySecretPassword", ssid: "MySSID"}]
           }}
        ]
      """)
    end
  end
end
