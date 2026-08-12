# SPDX-FileCopyrightText: 2026 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.HaLow do
  @moduledoc """
  VintageNet technology for WiFi HaLow (IEEE 802.11ah / sub-GHz "S1G").

  HaLow is not a distinct networking stack: it is `VintageNetWiFi` driven
  through a vendor `wpa_supplicant` fork (e.g. Morse Micro's
  `wpa_supplicant_s1g`) with a few extra S1G network keys, a different binary
  name, and `nl80211`-only driver flags. Both **AP** and **STA** run entirely
  through `wpa_supplicant` (no `hostapd`), reusing
  `VintageNetWiFi.WPASupplicant`.

  All HaLow-specific knobs live in the per-interface configuration map (there is
  no `Application` environment). See `VintageNetWiFi.HaLow.Config` for the full
  set of options and defaults.

  ## Configuration

  A HaLow access point:

  ```elixir
  %{
    type: VintageNetWiFi.HaLow,
    vintage_net_wifi_halow: %{
      mode: :ap,
      ssid: "halow-ap",
      country: "US",
      channel: 14,
      op_class: 69,
      key_mgmt: :sae,
      passphrase: "a-strong-passphrase"
    },
    ipv4: %{method: :static, address: {192, 168, 40, 1}, prefix_length: 24},
    dhcpd: %{start: {192, 168, 40, 10}, end: {192, 168, 40, 100}}
  }
  ```

  A HaLow station (STA):

  ```elixir
  %{
    type: VintageNetWiFi.HaLow,
    vintage_net_wifi_halow: %{
      mode: :sta,
      ssid: "halow-ap",
      key_mgmt: :sae,
      passphrase: "a-strong-passphrase"
    },
    ipv4: %{method: :dhcp}
  }
  ```

  An AP-less peer link (IBSS / ad-hoc, `mode: :ibss`). Two nodes on the same
  channel talk directly with no AP. The fork derives the frequency from the S1G
  `channel`, so set `channel`/`op_class` for your regulatory domain (the Morse
  fork defaults ad-hoc to `channel: 44`, `op_class: 71`).

  ```elixir
  %{
    type: VintageNetWiFi.HaLow,
    vintage_net_wifi_halow: %{
      mode: :ibss,
      ssid: "halow-adhoc",
      channel: 44,
      op_class: 71,
      s1g_prim_1mhz_chan_index: 3
    },
    ipv4: %{method: :static, address: {192, 168, 41, 1}, prefix_length: 24}
  }
  ```

  ## System requirements

  This technology needs a vendor S1G `wpa_supplicant` fork on `PATH` (default
  binary name `wpa_supplicant_s1g`, overridable per-interface). The out-of-tree
  Morse driver + firmware and, for optional tunables, `morse_cli` are system
  integration concerns handled by the Nerves system, not this library.
  """
  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  alias VintageNet.IP.DhcpdConfig
  alias VintageNet.IP.DnsdConfig
  alias VintageNet.IP.IPv4Config
  alias VintageNetWiFi.HaLow.Config
  alias VintageNetWiFi.HaLow.MorseCli
  alias VintageNetWiFi.HaLow.SupplicantConf
  alias VintageNetWiFi.WPASupplicant

  @impl VintageNet.Technology
  def normalize(%{type: __MODULE__} = config) do
    halow =
      config
      |> Map.get(:vintage_net_wifi_halow, %{})
      |> Map.put_new(:mode, :ap)

    %{type: __MODULE__, vintage_net_wifi_halow: halow}
    |> copy_ip_keys(config)
    |> IPv4Config.normalize()
    |> DhcpdConfig.normalize()
    |> DnsdConfig.normalize()
  end

  defp copy_ip_keys(normalized, config) do
    Enum.reduce([:ipv4, :dhcpd, :dnsd], normalized, fn key, acc ->
      case Map.fetch(config, key) do
        {:ok, value} -> Map.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  @impl VintageNet.Technology
  def to_raw_config(ifname, %{type: __MODULE__} = config, opts) do
    tmpdir = Keyword.fetch!(opts, :tmpdir)
    normalized_config = normalize(config)

    ctrl_dir = Path.join(tmpdir, "wpa_supplicant")

    halow_config =
      ifname
      |> Config.new(normalized_config.vintage_net_wifi_halow)
      |> Map.put(:ctrl_interface, ctrl_dir)

    conf_path = Path.join(tmpdir, "wpa_supplicant.conf.#{ifname}")

    wpa_supplicant_options = [
      wpa_supplicant: halow_config.wpa_supplicant,
      ifname: ifname,
      wpa_supplicant_conf_path: conf_path,
      control_path: ctrl_dir,
      driver_flags: halow_config.driver_flags,
      ap_mode: halow_config.mode in [:ap, :ibss],
      verbose: false
    ]

    %RawConfig{
      ifname: ifname,
      type: __MODULE__,
      source_config: normalized_config,
      required_ifnames: [ifname],
      restart_strategy: :rest_for_one,
      files: [{conf_path, IO.iodata_to_binary(SupplicantConf.build(halow_config))}],
      cleanup_files: [Path.join(ctrl_dir, ifname)],
      up_cmds: MorseCli.up_cmds(halow_config),
      child_specs: [{WPASupplicant, wpa_supplicant_options}]
    }
    |> IPv4Config.add_config(normalized_config, opts)
    |> DhcpdConfig.add_config(normalized_config, opts)
    |> DnsdConfig.add_config(normalized_config, opts)
  end

  @impl VintageNet.Technology
  def ioctl(ifname, :scan, _args) do
    WPASupplicant.scan(ifname)
  end

  def ioctl(ifname, :signal_poll, _args) do
    WPASupplicant.signal_poll(ifname)
  end

  def ioctl(_ifname, _command, _args) do
    {:error, :unsupported}
  end

  @impl VintageNet.Technology
  def check_system(_opts) do
    :ok
  end
end
