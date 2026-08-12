# SPDX-FileCopyrightText: 2026 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.HaLowTest do
  use ExUnit.Case, async: false

  import VintageNetWiFiTest.Utils

  alias VintageNet.Interface.RawConfig
  alias VintageNetWiFi.HaLow
  alias VintageNetWiFi.HaLow.Config
  alias VintageNetWiFi.HaLow.SupplicantConf
  alias VintageNetWiFi.WPASupplicant

  # Parse a generated wpa_supplicant.conf into {global_map, network_map}. Values
  # keep their raw right-hand side (quotes intact) so tests can assert exact
  # emitted text.
  defp parse_conf(iodata) do
    lines =
      iodata
      |> IO.iodata_to_binary()
      |> String.split("\n", trim: true)

    {net_lines, global_lines} =
      Enum.split_with(lines, &String.starts_with?(&1, "\t"))

    {kv(global_lines -- ["network={", "}"]), kv(net_lines)}
  end

  defp kv(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["network={", "}", ""]))
    |> Enum.map(fn line ->
      [k, v] = String.split(line, "=", parts: 2)
      {k, v}
    end)
    |> Map.new()
  end

  defp build(ifname, halow) do
    ifname
    |> Config.new(halow)
    |> Map.put(:ctrl_interface, "/tmp/wpa")
    |> SupplicantConf.build()
  end

  # RawConfig.child_specs can contain other children (e.g. a udhcpc map for
  # ipv4: dhcp), so pull out the WPASupplicant options explicitly.
  defp wpa_opts(%RawConfig{child_specs: specs}) do
    Enum.find_value(specs, fn
      {WPASupplicant, opts} -> opts
      _ -> nil
    end)
  end

  defp wpa_conf(%RawConfig{files: files}) do
    Enum.find_value(files, fn
      {path, contents} ->
        if String.contains?(path, "wpa_supplicant.conf."), do: {path, contents}

      _ ->
        nil
    end)
  end

  describe "SupplicantConf AP (mode=2)" do
    test "emits the validated S1G network-block keys" do
      {global, net} = parse_conf(build("wlan0", %{mode: :ap, ssid: "halow", frequency: 5260}))

      assert global["country"] == "US"
      # op_class must be global for AP mode (verified on live MM8108), not in
      # the network block.
      assert global["op_class"] == "69"
      assert net["ssid"] == "\"halow\""
      assert net["mode"] == "2"
      assert net["frequency"] == "5260"
      refute Map.has_key?(net, "op_class")
      assert net["s1g_prim_chwidth"] == "0"
      assert net["s1g_prim_1mhz_chan_index"] == "0"
    end

    test "open AP uses key_mgmt=NONE and omits wpa keys" do
      {_global, net} = parse_conf(build("wlan0", %{mode: :ap, ssid: "open", key_mgmt: :none}))

      assert net["key_mgmt"] == "NONE"
      refute Map.has_key?(net, "sae_password")
      refute Map.has_key?(net, "psk")
    end

    test "SAE AP emits WPA3 keys" do
      {_global, net} =
        parse_conf(
          build("wlan0", %{mode: :ap, ssid: "secure", key_mgmt: :sae, passphrase: "supersecret"})
        )

      assert net["key_mgmt"] == "SAE"
      assert net["ieee80211w"] == "2"
      assert net["sae_password"] == "\"supersecret\""
    end

    test "WPA-PSK AP emits psk" do
      {_global, net} =
        parse_conf(
          build("wlan0", %{mode: :ap, ssid: "psk", key_mgmt: :wpa_psk, passphrase: "hunter2xy"})
        )

      assert net["key_mgmt"] == "WPA-PSK"
      assert net["psk"] == "\"hunter2xy\""
    end

    test "hidden AP sets ignore_broadcast_ssid" do
      {_global, net} = parse_conf(build("wlan0", %{mode: :ap, ssid: "h", hidden: true}))
      assert net["ignore_broadcast_ssid"] == "1"
    end

    test "disable_s1g_sgi omitted when 0, emitted when 1" do
      {_g, net0} = parse_conf(build("wlan0", %{mode: :ap, ssid: "a"}))
      refute Map.has_key?(net0, "disable_s1g_sgi")

      {_g, net1} = parse_conf(build("wlan0", %{mode: :ap, ssid: "a", disable_s1g_sgi: 1}))
      assert net1["disable_s1g_sgi"] == "1"
    end
  end

  describe "SupplicantConf STA" do
    test "STA is managed (no mode=2) and sets ap_scan" do
      conf = build("wlan0", %{mode: :sta, ssid: "halow"}) |> IO.iodata_to_binary()
      {global, net} = parse_conf(conf)

      assert global["ap_scan"] == "1"
      refute Map.has_key?(net, "mode")
      assert net["ssid"] == "\"halow\""
    end

    test "STA SAE emits sae_password" do
      {_global, net} =
        parse_conf(
          build("wlan0", %{mode: :sta, ssid: "s", key_mgmt: :sae, passphrase: "pw123456"})
        )

      assert net["key_mgmt"] == "SAE"
      assert net["sae_password"] == "\"pw123456\""
    end
  end

  describe "SupplicantConf IBSS (mode=1, AP-less)" do
    test "emits mode=1 with network-block channel + op_class (not global)" do
      {global, net} =
        parse_conf(
          build("wlan1", %{
            mode: :ibss,
            ssid: "adhoc",
            channel: 44,
            op_class: 71,
            s1g_prim_1mhz_chan_index: 3
          })
        )

      # IBSS reads op_class from the network block (ssid->op_class), so it must
      # NOT appear in the global section.
      refute Map.has_key?(global, "op_class")
      assert net["mode"] == "1"
      assert net["channel"] == "44"
      assert net["op_class"] == "71"
      assert net["s1g_prim_1mhz_chan_index"] == "3"
      # The fork derives frequency from channel, so no frequency= is emitted.
      refute Map.has_key?(net, "frequency")
    end

    test "IBSS SAE emits sae_password" do
      {_g, net} =
        parse_conf(
          build("wlan1", %{mode: :ibss, ssid: "s", key_mgmt: :sae, passphrase: "pw123456"})
        )

      assert net["mode"] == "1"
      assert net["key_mgmt"] == "SAE"
      assert net["sae_password"] == "\"pw123456\""
    end
  end

  describe "to_raw_config/3" do
    test "AP: single WPASupplicant child with S1G binary + nl80211 driver flags" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{mode: :ap, ssid: "halow-ap", frequency: 5260},
        ipv4: %{method: :static, address: {192, 168, 40, 1}, prefix_length: 24}
      }

      raw = HaLow.to_raw_config("wlan0", input, default_opts())
      opts = wpa_opts(raw)
      {path, contents} = wpa_conf(raw)

      assert opts[:wpa_supplicant] == "wpa_supplicant_s1g"
      assert opts[:driver_flags] == "nl80211"
      assert opts[:ap_mode] == true
      assert opts[:ifname] == "wlan0"

      assert String.ends_with?(path, "wpa_supplicant.conf.wlan0")
      assert contents =~ "mode=2"
      assert contents =~ "op_class=69"
    end

    test "STA: ap_mode false" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{mode: :sta, ssid: "halow-ap"},
        ipv4: %{method: :dhcp}
      }

      opts = wpa_opts(HaLow.to_raw_config("wlan0", input, default_opts()))

      assert opts[:ap_mode] == false
      assert opts[:driver_flags] == "nl80211"
    end

    test "IBSS: ap_mode true (AP-style control interface)" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{mode: :ibss, ssid: "adhoc", channel: 44, op_class: 71},
        ipv4: %{method: :dhcp}
      }

      raw = HaLow.to_raw_config("wlan1", input, default_opts())
      opts = wpa_opts(raw)
      {_path, contents} = wpa_conf(raw)

      assert opts[:ap_mode] == true
      assert contents =~ "mode=1"
      assert contents =~ "channel=44"
    end

    test "binary + driver flags are overridable per-interface (no Application env)" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{
          mode: :ap,
          ssid: "x",
          wpa_supplicant: "my_wpa",
          driver_flags: "nl80211,wext"
        },
        ipv4: %{method: :dhcp}
      }

      opts = wpa_opts(HaLow.to_raw_config("wlan0", input, default_opts()))

      assert opts[:wpa_supplicant] == "my_wpa"
      assert opts[:driver_flags] == "nl80211,wext"
    end

    test "optional morse_cli duty-cycle attaches as an ignore-errors up_cmd" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{mode: :ap, ssid: "x", duty_cycle: :spread},
        ipv4: %{method: :dhcp}
      }

      %RawConfig{up_cmds: up_cmds} = HaLow.to_raw_config("wlan0", input, default_opts())

      assert {:run_ignore_errors, "morse_cli", ["-i", "wlan0", "duty_cycle", "enable", "-m", "0"]} in up_cmds
    end

    test "no duty cycle => no morse_cli up_cmds" do
      input = %{
        type: HaLow,
        vintage_net_wifi_halow: %{mode: :ap, ssid: "x"},
        ipv4: %{method: :dhcp}
      }

      %RawConfig{up_cmds: up_cmds} = HaLow.to_raw_config("wlan0", input, default_opts())
      refute Enum.any?(up_cmds, &match?({:run_ignore_errors, "morse_cli", _}, &1))
    end
  end

  describe "normalize/1" do
    test "defaults mode to :ap and normalizes IP config" do
      input = %{type: HaLow, vintage_net_wifi_halow: %{ssid: "x"}, ipv4: %{method: :dhcp}}
      normalized = HaLow.normalize(input)
      assert normalized.vintage_net_wifi_halow.mode == :ap
    end
  end
end
