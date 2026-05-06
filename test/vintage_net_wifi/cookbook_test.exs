# SPDX-FileCopyrightText: 2021 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.CookbookTest do
  use ExUnit.Case

  alias VintageNetWiFi.Cookbook

  test "generic/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{
                networks: [
                  %{
                    key_mgmt: [:wpa_psk, :wpa_psk_sha256, :sae],
                    psk: "my_passphrase",
                    ssid: "my_ssid",
                    ieee80211w: 1,
                    sae_password: "my_passphrase"
                  }
                ]
              }
            }} == Cookbook.generic("my_ssid", "my_passphrase")
  end

  test "open_wifi/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{networks: [%{key_mgmt: :none, ssid: "free_wifi"}]}
            }} == Cookbook.open_wifi("free_wifi")

    assert {:error, :ssid_too_short} == Cookbook.open_wifi("")
  end

  test "wpa_psk/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{
                networks: [%{key_mgmt: :wpa_psk, psk: "my_passphrase", ssid: "my_ssid"}]
              }
            }} == Cookbook.wpa_psk("my_ssid", "my_passphrase")
  end

  test "wpa3_sae/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{
                networks: [
                  %{key_mgmt: :sae, ieee80211w: 2, sae_password: "my_passphrase", ssid: "my_ssid"}
                ]
              }
            }} == Cookbook.wpa3_sae("my_ssid", "my_passphrase")
  end

  test "wpa_eap_peap/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{
                networks: [
                  %{
                    key_mgmt: :wpa_eap,
                    ssid: "corp_wifi",
                    eap: "PEAP",
                    identity: "username",
                    password: "password",
                    phase2: "auth=MSCHAPV2"
                  }
                ]
              }
            }} == Cookbook.wpa_eap_peap("corp_wifi", "username", "password")
  end

  test "open_access_point/2" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{address: {192, 168, 24, 1}, method: :static, netmask: {255, 255, 255, 0}},
              dhcpd: %{end: {192, 168, 24, 250}, start: {192, 168, 24, 10}},
              vintage_net_wifi: %{networks: [%{key_mgmt: :none, mode: :ap, ssid: "my_network"}]}
            }} == Cookbook.open_access_point("my_network")

    assert {:ok,
            %{
              type: VintageNetWiFi,
              ipv4: %{address: {10, 1, 2, 1}, method: :static, netmask: {255, 255, 255, 0}},
              dhcpd: %{end: {10, 1, 2, 250}, start: {10, 1, 2, 10}},
              vintage_net_wifi: %{networks: [%{key_mgmt: :none, mode: :ap, ssid: "another_net"}]}
            }} == Cookbook.open_access_point("another_net", "10.1.2.3")
  end

  test "with_mac_address/2 layers a MAC onto a recipe" do
    assert {:ok,
            %{
              type: VintageNetWiFi,
              mac_address: "aa:bb:cc:dd:ee:ff",
              ipv4: %{method: :dhcp},
              vintage_net_wifi: %{
                networks: [%{key_mgmt: :wpa_psk, psk: "my_passphrase", ssid: "my_ssid"}]
              }
            }} ==
             "my_ssid"
             |> Cookbook.wpa_psk("my_passphrase")
             |> Cookbook.with_mac_address("aa:bb:cc:dd:ee:ff")
  end

  test "with_mac_address/2 accepts an MFArgs tuple" do
    mfa = {String, :downcase, ["AA:BB:CC:DD:EE:FF"]}

    assert {:ok, %{mac_address: ^mfa}} =
             Cookbook.wpa_psk("my_ssid", "my_passphrase") |> Cookbook.with_mac_address(mfa)
  end

  test "with_mac_address/2 rejects an invalid MAC" do
    assert {:error, :invalid_mac_address} ==
             Cookbook.wpa_psk("my_ssid", "my_passphrase") |> Cookbook.with_mac_address("nope")
  end

  test "with_mac_address/2 passes upstream errors through" do
    assert {:error, :ssid_too_short} ==
             Cookbook.open_wifi("") |> Cookbook.with_mac_address("aa:bb:cc:dd:ee:ff")
  end
end
