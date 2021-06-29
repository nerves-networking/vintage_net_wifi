# Changelog

## v0.10.2

* Bug fixes
  * Added missing EAP WiFi types. Thanks to Dömötör Gulyás for this fix.

## v0.10.1

* New features
  * It's now possible to specify arbitrary `wpa_supplicant.conf` text.
    VintageNetWiFi normally tries to validate everything going into the config
    file, but this gets in the way of advanced users especially when a feature
    is not available in VintageNetWiFi yet. This is the escape hatch. Specify
    the `:wpa_supplicant_conf` key in the config and you have total control.
  * Initial support for WPA3 has been added. See the `README.md` for
    configuration details. Note that many WiFi modules and their drivers don't
    support WPA3 yet, and WPA3 support isn't enabled at the time of this release
    in all official Nerves systems.

## v0.10.0

This release is backwards compatible with v0.9.2. No changes are needed to
existing code.

* Bug fixes
  * OTP 24 is supported now. This release updates to the old crypto API that has
    been removed in OTP 24.
  * Fix a GenServer crash when requesting BSSID information. This issue seemed
    to occur more frequently in high density WiFi environments. OTP supervision
    recovered it, but it had a side effect of making VintageNet send out
    notifications that would make it look like the interface bounced.
  * Fix a crash due to invalid AP flags being reported. Thanks to Rick Carlino
    for reporting that this happens.

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

