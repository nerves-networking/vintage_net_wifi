# 🍇 VintageNetWiFi

[![Hex version](https://img.shields.io/hexpm/v/vintage_net_wifi.svg "Hex version")](https://hex.pm/packages/vintage_net_wifi)
[![API docs](https://img.shields.io/hexpm/v/vintage_net_wifi.svg?label=hexdocs "API docs")](https://hexdocs.pm/vintage_net_wifi/VintageNet.html)
[![CircleCI](https://circleci.com/gh/nerves-networking/vintage_net_wifi.svg?style=svg)](https://circleci.com/gh/nerves-networking/vintage_net_wifi)

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

You'll probably want to configure WiFi at runtime, but for local development and
getting started for the first time, it's convenient to configure WiFi at compile
time. To do this, add the following to your `:vintage_net` configuration:

```elixir
  config :vintage_net, [
    config: [
      {"wlan0",
       %{type: VintageNetWiFi,
         wifi: %{
         key_mgmt: :wpa_psk,
         ssid: "my_network_ssid"
         psk: "secret_password",
       },
       ipv4: %{
         method: :dhcp
       }
      }
    ]
  ]
```

Fill in the `:ssid` and `:psk` for your network, build your application, update
your device, and VintageNet will try to connect to your network.

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
