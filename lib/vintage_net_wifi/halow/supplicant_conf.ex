# SPDX-FileCopyrightText: 2026 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.HaLow.SupplicantConf do
  @moduledoc """
  Builds `wpa_supplicant` configuration for WiFi HaLow (802.11ah / S1G).

  A single generator handles both roles:

  * **STA** (`mode: :sta`) - a managed station (`mode=0`) that scans for and
    associates to a HaLow AP.
  * **AP** (`mode: :ap`) - an access point run entirely by `wpa_supplicant`
    (`mode=2`), matching how `VintageNetWiFi` already does AP mode. No `hostapd`
    is required.

  The S1G network-block keys emitted here (`op_class`, `s1g_prim_chwidth`,
  `s1g_prim_1mhz_chan_index`, `disable_s1g_sgi`) are the exact fields the Morse
  Micro `wpa_supplicant` fork (`wpa_supplicant_s1g`) registers in its network
  block parser. `ieee80211ah` is **not** a network-block key for
  `wpa_supplicant` (unlike `hostapd`); S1G operation is implied by the presence
  of these fields together with an S1G driver.

  > #### AP-via-wpa_supplicant needs hardware validation {: .warning}
  >
  > Morse documents/tests `hostapd` for AP. Driving an S1G AP purely through
  > `wpa_supplicant` (`mode=2`) with a `frequency=` (shadow-5 GHz) network block
  > is architecturally supported by the fork but less-trodden. Validate the
  > generated file against a live GW16167 before relying on it.
  """

  alias VintageNetWiFi.HaLow.Config

  @doc """
  Build `wpa_supplicant` config file contents (as an `iolist`) for `config`.
  """
  @spec build(Config.t()) :: iolist()
  def build(%Config{} = config) do
    [
      global_lines(config),
      "",
      "network={",
      network_lines(config),
      "}"
    ]
    |> List.flatten()
    |> Enum.map(&[&1, "\n"])
  end

  defp global_lines(%Config{mode: :ap} = config) do
    # For AP mode the fork reads `op_class` from the *global* config
    # (`wpa_s->conf->op_class`), not the network block. Emitting it here is
    # required or wpa_supplicant refuses to start the AP
    # ("op_class not set. Need op_class to start as AP"). Verified on a live
    # MM8108 (GW16167): op_class=69, frequency=5260 (shadow ch52) => S1G ch14.
    [
      "ctrl_interface=#{config.ctrl_interface}",
      "country=#{config.country}",
      "op_class=#{config.op_class}"
    ]
  end

  defp global_lines(%Config{mode: :sta} = config) do
    [
      "ctrl_interface=#{config.ctrl_interface}",
      "country=#{config.country}",
      "ap_scan=1"
    ]
  end

  # IBSS/mesh read op_class from the *network* block (ssid->op_class), not the
  # global config, so only ctrl_interface + country are needed globally.
  defp global_lines(%Config{mode: :ibss} = config) do
    [
      "ctrl_interface=#{config.ctrl_interface}",
      "country=#{config.country}"
    ]
  end

  defp network_lines(%Config{mode: :ap} = config) do
    # NOTE: op_class is emitted at the global level (see global_lines/1), not
    # here, because wpa_supplicant AP mode reads it from wpa_s->conf.
    [
      "\tssid=\"#{config.ssid}\"",
      "\tmode=2",
      frequency_line(config),
      "\ts1g_prim_chwidth=#{config.s1g_prim_chwidth}",
      "\ts1g_prim_1mhz_chan_index=#{config.s1g_prim_1mhz_chan_index}",
      disable_sgi_line(config),
      beacon_line(config),
      dtim_line(config),
      hidden_line(config)
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(security_network_lines(config))
    |> Kernel.++(extra_lines(config))
  end

  # IBSS (ad-hoc, mode=1): AP-less peer link. The fork derives the shadow
  # frequency from the S1G `channel` (morse_ibss_mesh_setup_freq), so emit
  # `channel` + network-block `op_class` (ssid->op_class) rather than
  # `frequency`. Source-derived from the Morse fork; not yet hardware-associated
  # (needs two S1G nodes on one channel).
  defp network_lines(%Config{mode: :ibss} = config) do
    [
      "\tssid=\"#{config.ssid}\"",
      "\tmode=1",
      "\tchannel=#{config.channel}",
      "\top_class=#{config.op_class}",
      "\ts1g_prim_chwidth=#{config.s1g_prim_chwidth}",
      "\ts1g_prim_1mhz_chan_index=#{config.s1g_prim_1mhz_chan_index}",
      disable_sgi_line(config)
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(security_network_lines(config))
    |> Kernel.++(extra_lines(config))
  end

  defp network_lines(%Config{mode: :sta} = config) do
    [
      "\tssid=\"#{config.ssid}\"",
      frequency_line(config),
      s1g_sta_hint(config, :op_class),
      s1g_sta_hint(config, :s1g_prim_chwidth),
      s1g_sta_hint(config, :s1g_prim_1mhz_chan_index)
    ]
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(security_network_lines(config))
    |> Kernel.++(extra_lines(config))
  end

  # --- shared field emitters ---

  defp frequency_line(%Config{frequency: nil}), do: nil
  defp frequency_line(%Config{frequency: freq}), do: "\tfrequency=#{freq}"

  defp disable_sgi_line(%Config{disable_s1g_sgi: 0}), do: nil
  defp disable_sgi_line(%Config{disable_s1g_sgi: v}), do: "\tdisable_s1g_sgi=#{v}"

  defp beacon_line(%Config{beacon_int: nil}), do: nil
  defp beacon_line(%Config{beacon_int: v}), do: "\tbeacon_int=#{v}"

  defp dtim_line(%Config{dtim_period: nil}), do: nil
  defp dtim_line(%Config{dtim_period: v}), do: "\tdtim_period=#{v}"

  defp hidden_line(%Config{hidden: true}), do: "\tignore_broadcast_ssid=1"
  defp hidden_line(%Config{hidden: false}), do: nil

  # STA emits the S1G network-block hints whenever set (defaults are non-nil).
  # These are valid `wpa_supplicant_s1g` network fields and help the driver
  # pick the right S1G operating point; a nil value is simply omitted.
  defp s1g_sta_hint(config, key) do
    case Map.get(config, key) do
      nil -> nil
      value -> "\t#{key}=#{value}"
    end
  end

  defp security_network_lines(%Config{key_mgmt: :none}), do: ["\tkey_mgmt=NONE"]

  defp security_network_lines(%Config{key_mgmt: :sae, passphrase: passphrase}) do
    [
      "\tkey_mgmt=SAE",
      "\tieee80211w=2",
      "\tsae_password=\"#{passphrase}\""
    ]
  end

  defp security_network_lines(%Config{key_mgmt: :wpa_psk, passphrase: passphrase}) do
    [
      "\tkey_mgmt=WPA-PSK",
      "\tpsk=\"#{passphrase}\""
    ]
  end

  defp extra_lines(%Config{extra_options: opts}) when is_list(opts) do
    Enum.map(opts, &"\t#{&1}")
  end
end
