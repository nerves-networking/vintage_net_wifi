# SPDX-FileCopyrightText: 2026 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.HaLow.Config do
  @moduledoc """
  Normalized WiFi HaLow (802.11ah / S1G) configuration.

  This is the internal, validated representation of the user-supplied
  `:vintage_net_wifi_halow` map. Use `new/2` to build it from user config with
  defaults filled in.

  All HaLow-specific knobs live here (per-interface), including the binary
  names and driver flags, so no `Application` environment is required. The
  defaults mirror a known-good Gateworks GW16167 (MM8108) US baseline.
  """

  @enforce_keys [:ifname, :mode]
  defstruct ifname: nil,
            mode: :ap,
            ssid: nil,
            country: "US",
            # Shadow-5 GHz frequency (MHz) the Morse driver presents this S1G
            # channel as. Required for wpa_supplicant AP (mode=2); optional for
            # STA. nil => not emitted (STA scans for it).
            frequency: nil,
            channel: 14,
            op_class: 69,
            s1g_prim_chwidth: 0,
            s1g_prim_1mhz_chan_index: 0,
            disable_s1g_sgi: 0,
            beacon_int: 1000,
            dtim_period: 1,
            hidden: false,
            key_mgmt: :none,
            passphrase: nil,
            # duty cycle: nil (driver default) | :spread | :burst | :disable
            duty_cycle: nil,
            # Binary + driver knobs (per-interface, not Application env).
            wpa_supplicant: "wpa_supplicant_s1g",
            morse_cli: "morse_cli",
            # S1G drivers/kernels frequently lack wireless-extensions, so use
            # nl80211 only (not the default "nl80211,wext").
            driver_flags: "nl80211",
            ctrl_interface: nil,
            extra_options: []

  @type mode :: :ap | :sta | :ibss
  @type key_mgmt :: :none | :sae | :wpa_psk

  @type t :: %__MODULE__{
          ifname: String.t(),
          mode: mode(),
          ssid: String.t() | nil,
          country: String.t(),
          frequency: non_neg_integer() | nil,
          channel: non_neg_integer(),
          op_class: non_neg_integer(),
          s1g_prim_chwidth: 0..2,
          s1g_prim_1mhz_chan_index: non_neg_integer(),
          disable_s1g_sgi: 0 | 1,
          beacon_int: pos_integer(),
          dtim_period: pos_integer(),
          hidden: boolean(),
          key_mgmt: key_mgmt(),
          passphrase: String.t() | nil,
          duty_cycle: nil | :spread | :burst | :disable,
          wpa_supplicant: String.t(),
          morse_cli: String.t(),
          driver_flags: String.t(),
          ctrl_interface: String.t() | nil,
          extra_options: [String.t()]
        }

  @doc """
  Build a normalized config from the user-supplied `:vintage_net_wifi_halow`
  map for `ifname`.

  `ctrl_interface` is supplied by the caller (the technology module) since it
  depends on the runtime tmp dir.
  """
  @spec new(String.t(), map()) :: t()
  def new(ifname, halow) when is_binary(ifname) and is_map(halow) do
    fields =
      halow
      |> Map.take(known_keys())
      |> Map.put(:ifname, ifname)
      |> Map.put_new(:mode, :ap)

    struct!(__MODULE__, fields)
  end

  defp known_keys() do
    %__MODULE__{ifname: "x", mode: :ap}
    |> Map.from_struct()
    |> Map.keys()
  end
end
