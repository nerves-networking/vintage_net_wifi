# SPDX-FileCopyrightText: 2026 Eliel A. Gordon
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.MacAddressConfig do
  @moduledoc """
  MAC Address utilities and config integration for `VintageNetWiFi`.

  Exposes `normalize/1` and `add_config/3` so that `:mac_address` plugs into
  the technology config pipeline alongside `VintageNet.IP.IPv4Config` and
  friends.
  """

  alias VintageNet.Interface.RawConfig

  require Logger

  @typedoc """
  A MAC address is a string of the form "aa:bb:cc:dd:ee:ff"
  """
  @type t() :: <<_::136>>

  @doc """
  Validate the `:mac_address` slice of a technology configuration.

  Returns the config unchanged when `:mac_address` is unset or holds a valid
  MAC string / MFArgs tuple. Raises `ArgumentError` otherwise.
  """
  @spec normalize(map()) :: map()
  def normalize(%{mac_address: mac} = config) do
    if valid_mac?(mac) or mfargs?(mac) do
      config
    else
      raise ArgumentError, "Invalid MAC address #{inspect(mac)}"
    end
  end

  def normalize(config), do: config

  @doc """
  Append MAC address up_cmds to the given `RawConfig`.

  When `:mac_address` is set, this brings the interface down, sets the new
  hardware address, and lets the rest of the pipeline (`IPv4Config.add_config`
  and the `WPASupplicant` child_spec) bring it back up. If the resolved value
  isn't a valid MAC, it's logged and skipped.
  """
  @spec add_config(RawConfig.t(), map(), keyword()) :: RawConfig.t()
  def add_config(raw_config, config, opts \\ [])

  def add_config(%RawConfig{} = raw_config, %{mac_address: mac_address}, _opts) do
    resolved_mac = resolve(mac_address)

    if valid_mac?(resolved_mac) do
      Logger.info(
        "vintage_net_wifi: setting #{raw_config.ifname} MAC to #{resolved_mac}; forcing mac_addr=0/preassoc_mac_addr=0 in wpa_supplicant.conf"
      )

      # Bring the interface down before changing the MAC. Some WiFi drivers
      # reject address changes while the interface is up. IPv4Config.add_config
      # appends `ip link set <ifname> up` afterwards, and the WPASupplicant
      # child_spec only starts after up_cmds run, so the supplicant sees the
      # new MAC.
      new_up_cmds =
        raw_config.up_cmds ++
          [
            {:run_ignore_errors, "ip", ["link", "set", raw_config.ifname, "down"]},
            {:run, "ip", ["link", "set", raw_config.ifname, "address", resolved_mac]}
          ]

      %{raw_config | up_cmds: new_up_cmds}
    else
      Logger.warning("vintage_net_wifi: ignoring invalid MAC address '#{inspect(resolved_mac)}'")

      raw_config
    end
  end

  def add_config(%RawConfig{} = raw_config, _config, _opts), do: raw_config

  @doc """
  Return true if `:mac_address` is set on the config.
  """
  @spec set?(map()) :: boolean()
  def set?(config), do: Map.has_key?(config, :mac_address)

  @doc """
  Return true if this is a valid MAC address
  """
  @spec valid_mac?(any()) :: boolean()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def valid_mac?(<<a, b, ?:, c, d, ?:, e, f, ?:, g, h, ?:, i, j, ?:, k, l>>) do
    valid_hex?(a) and
      valid_hex?(b) and
      valid_hex?(c) and
      valid_hex?(d) and
      valid_hex?(e) and
      valid_hex?(f) and
      valid_hex?(g) and
      valid_hex?(h) and
      valid_hex?(i) and
      valid_hex?(j) and
      valid_hex?(k) and
      valid_hex?(l)
  end

  def valid_mac?(_), do: false

  @doc """
  Return true if the value is an MFArgs tuple (`{module, function, args}`)
  whose `apply/3` should yield a MAC address string at config-apply time.
  """
  @spec mfargs?(any()) :: boolean()
  def mfargs?({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a), do: true
  def mfargs?(_), do: false

  @doc """
  Resolve a MAC address that may be a string or an MFArgs tuple.

  Strings are returned as-is. MFArgs tuples are applied; if the call raises,
  the returned `{:error, exception}` will fail `valid_mac?/1` and let the caller
  log and skip the MAC change.
  """
  @spec resolve(t() | {module(), atom(), list()}) :: any()
  def resolve({m, f, args}) do
    apply(m, f, args)
  rescue
    e -> {:error, e}
  end

  def resolve(mac_address), do: mac_address

  defp valid_hex?(a)
       when a in [
              ?0,
              ?1,
              ?2,
              ?3,
              ?4,
              ?5,
              ?6,
              ?7,
              ?8,
              ?9,
              ?a,
              ?A,
              ?b,
              ?B,
              ?c,
              ?C,
              ?d,
              ?D,
              ?e,
              ?E,
              ?f,
              ?F
            ],
       do: true

  defp valid_hex?(_), do: false
end
