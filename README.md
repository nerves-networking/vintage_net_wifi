# 🍇 VintageNetWiFi

[![Hex version](https://img.shields.io/hexpm/v/vintage_net_wifi.svg "Hex version")](https://hex.pm/packages/vintage_net_wifi)
[![API docs](https://img.shields.io/hexpm/v/vintage_net_wifi.svg?label=hexdocs "API docs")](https://hexdocs.pm/vintage_net_wifi/VintageNet.html)
[![CircleCI](https://circleci.com/gh/nerves-networking/vintage_net_wifi.svg?style=svg)](https://circleci.com/gh/nerves-networking/vintage_net_wifi)
[![Coverage Status](https://coveralls.io/repos/github/nerves-networking/vintage_net_wifi/badge.svg?branch=master)](https://coveralls.io/github/nerves-networking/vintage_net_wifi?branch=master)

`VintageNetWiFi` makes it easy to add WiFi support for your device. This can be
as simple as connecting to a WiFi access point or starting a WiFi access point
so that other computers can connect directly.

You will need a WiFi module to use this library. If you're using Nerves, the
official Raspberry Pi and Beaglebone systems contain WiFi drivers for built-in
modules. If you are using a USB WiFi module, make sure that the Linux device
driver for that module is loaded and any required firmware is available.

Once that's done, all that you need to do is add `:vintage_net_wifi` to your
`mix` dependencies like this:

```elixir
def deps do
  [
    {:vintage_net_wifi, "~> 0.7.0", targets: @all_targets}
  ]
end
```

> VintageNetWiFi also requires that the `wpa_supplicant` package and necessary
> WiFi kernel modules are included in the system. All officially supported
> Nerves systems that run on hardware with WiFI should work.
>
> In Buildroot, check that `BR2_PACKAGE_WPA_SUPPLICANT` is enabled.
>
> If you are using access point mode, check that `CONFIG_UDHCPD` is enabled
> in Busybox and `BR2_PACKAGE_WPA_SUPPLICANT_HOTSPOT` is enabled in Buildroot.

WiFi network interfaces typically have names like `"wlan0"` or `"wlan1"` when
using Nerves. Most of the time, there's only one WiFi interface and its
`"wlan0"`. Some WiFi adapters expose separate interfaces for 2.4 GHz and 5 GHz
and they can be configured independently.

An example WiFi configuration looks like this:

```elixir
config :vintage_net,
  config: [
    {"wlan0",
     %{
       type: VintageNetWiFi,
       vintage_net_wifi: %{
         key_mgmt: :wpa_psk,
         psk: "a_passphrase_or_psk",
         ssid: "my_network_ssid"
       },
       ipv4: %{
         method: :dhcp
       }
     }}
  ]
```

The `:ipv4` key is handled by `vintage_net` to set the IP address on the
connection. Most of the time, you'll want to use DHCP to dynamically get an IP
address.

The `:vintage_net_wifi` key has the following common fields:

* `:ap_scan` -  See `wpa_supplicant` documentation. The default for this, 1,
  should work for nearly all users.
* `:bgscan` - Periodic background scanning to support roaming within an ESS.
  * `:simple`
  * `{:simple, args}` - args is a string to be passed to the `simple` wpa module
  * `:learn`
  * `{:learn, args}` args is a string to be passed to the `learn` wpa module
* `:passive_scan`
  * 0:  Do normal scans (allow active scans) (default)
  * 1:  Do passive scans.
* `:regulatory_domain`: Two character country code. Technology configuration
  will take priority over Application configuration
* `:networks` - A list of Wi-Fi networks to configure. In client mode,
  VintageNet connects to the first available network in the list. In host mode,
  the list should have one entry with SSID and password information.
  * `:mode` -
    * `:infrastructure` (default) - Normal operation. Associate with an AP
    * `:ap` - access point mode
    * `:ibss` - peer to peer mode (not supported)
  * `:ssid` - The SSID for the network
  * `:key_mgmt` - WiFi security mode (`:wpa_psk` for WPA2, `:none` for no
    password or WEP)
  * `:psk` - A WPA2 passphrase or the raw PSK. If a passphrase is passed in, it
    will be converted to a PSK and discarded.
  * `:priority` - The priority to set for a network if you are using multiple
    network configurations
  * `:scan_ssid` - Scan with SSID-specific Probe Request frames (this can be
    used to find APs that do not accept broadcast SSID or use multiple SSIDs;
    this will add latency to scanning, so enable this only when needed)
  * `:frequency` - When in `:ibss` mode, use this channel frequency (in MHz).
    For example, specify 2412 for channel 1.

See the [official
docs](https://w1.fi/cgit/hostap/plain/wpa_supplicant/wpa_supplicant.conf) for
the complete list of options.

Here's an example:

```elixir
iex> VintageNet.configure("wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            key_mgmt: :wpa_psk,
            psk: "a_passphrase_or_psk",
            ssid: "my_network_ssid"
          }
        ]
      },
      ipv4: %{method: :dhcp}
    })
```

Example of WEP:

```elixir
iex> VintageNet.configure("wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "my_network_ssid",
            wep_key0: "42FEEDDEAFBABEDEAFBEEFAA55",
            key_mgmt: :none,
            wep_tx_keyidx: 0
          }
        ]
      },
      ipv4: %{method: :dhcp}
    })
```

Enterprise Wi-Fi (WPA-EAP) support mostly passes through to the
`wpa_supplicant`. Instructions for enterprise network for Linux
should map. For example:

```elixir
iex> VintageNet.configure("wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            ssid: "testing",
            key_mgmt: :wpa_eap,
            pairwise: "CCMP TKIP",
            group: "CCMP TKIP",
            eap: "PEAP",
            identity: "user1",
            password: "supersecret",
            phase1: "peapver=auto",
            phase2: "MSCHAPV2"
          }
        ]
      },
      ipv4: %{method: :dhcp}
})
```

Network adapters that can run as an Access Point can be configured as follows:

```elixir
iex> VintageNet.configure("wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        networks: [
          %{
            mode: :ap,
            ssid: "test ssid",
            key_mgmt: :none
          }
        ]
      },
      ipv4: %{
        method: :static,
        address: "192.168.24.1",
        netmask: "255.255.255.0"
      },
      dhcpd: %{
        start: "192.168.24.2",
        end: "192.168.24.10"
      }
})
```

If your device may be installed in different countries, you should override the
default regulatory domain to the desired country at runtime.  VintageNet uses
the global domain by default and that will restrict the set of available WiFi
frequencies in some countries. For example:

```elixir
iex> VintageNet.configure("wlan0", %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{
        regulatory_domain: "US",
        networks: [
          %{
            ssid: "testing",
            key_mgmt: :wpa_psk,
            psk: "super secret"
          }
        ]
      },
      ipv4: %{method: :dhcp}
})
```

## Properties

In addition to the common `vintage_net` properties for all interface types, this technology reports the following:

Property        | Values           | Description
 -------------- | ---------------- | -----------
`access_points` | [%AccessPoint{}] | A list of access points as found by the most recent scan
`clients`       | ["11:22:33:44:55:66"] | A list of clients connected to the access point when using `mode: :ap`
`current_ap`    | %AccessPoint{}   | The currently associated access point

Access points are identified by their BSSID. Information about an access point
has the following form:

```elixir
%VintageNetWiFi.AccessPoint{
  band: :wifi_5_ghz,
  bssid: "8a:8a:20:88:7a:50",
  channel: 149,
  flags: [:wpa2_psk_ccmp, :ess],
  frequency: 5745,
  signal_dbm: -76,
  signal_percent: 57,
  ssid: "MyNetwork"
}
```

Applications can scan for access points in a couple ways. The first is to call
`VintageNet.scan("wlan0")`, wait for a second, and then call
`VintageNet.get(["interface", "wlan0", "access_points"])`. This works for
scanning networks once or twice. A better way is to subscribe to the
`"access_points"` property and then call `VintageNet.scan("wlan0")` on a timer.
The `"access_points"` property updates as soon as the WiFi module notifies that
it is complete so applications don't need to guess how long to wait.

## Debugging

Unfortunately, when you're getting started for the very first time, WiFi can be
quite frustrating. Error messages and logs are not all that helpful. The first
debugging step is to connect to your device (over a UART or USB Gadget or maybe
a wired Ethernet connection). Run:

```elixir
iex> VintageNet.info
```

Double check that all of your parameters are set correctly. The `:psk` cannot be
checked here, so if you suspect that's wrong, double check your `config.exs`.
The next step is to look at log messages for connection errors. On Nerves
devices, run `RingLogger.next` at the `IEx` prompt.
