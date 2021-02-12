# Changelog

## v0.9.2

This release introduces helper functions for configuring the most common types
of networks:

  * `VintageNetWiFi.quick_configure("ssid", "password")` - connect to a WPA PSK
    network on `"wlan0"`
  * `VintageNetWiFi.quick_scan()` - scan and return access points in one call

Additionally, there's now a `VintageNetWiFi.Cookbook` module with functions for
creating the configs for various kinds of networks.

## v0.9.1

* Bug fixes
  * Fix warnings when building with Elixir 1.11.

## v0.9.0

* New features
  * Initial support for 802.11s mesh networking. Please see the docs and the
    cookbook for using this since it requires compatible WiFi modules and more
    configuration than normal WiFi options.
  * Synchronize with vintage_net v0.9.0's networking program path API update

## v0.8.0

* New features
  * Add a WiFi signal strength polling feature. This works when connected to a
    WiFi access point.
  * Support vintage_net v0.8.0's `required_ifnames` API update

## v0.7.0

Initial `vintage_net_wifi` release. See the [`vintage_net v0.7.0` release
notes](https://github.com/nerves-networking/vintage_net/releases/tag/v0.7.0)
for upgrade instructions if you are a `vintage_net v0.6.x` user.

