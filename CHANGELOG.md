# Changelog

## v0.11.7 - 2023-10-04

* Fixed
  * Workaround issue passing SSIDs that contain a lot of escaped characters.
    These were probably invalid anyway, but this prevents needless retries.

* Changes
  * Lowered log priority (warning -> debug) of several messages that occur a lot
    and aren't really problems.

## v0.11.6 - 2023-03-08

* Fixed
  * Support passing SSIDs with all NULL characters to `wpa_supplicant`. This
    also fixes other SSIDs with nonprintable characters.

## v0.11.5 - 2023-03-08

* Fixed
  * Support SAE H2E and PK flags in AP advertisements

## v0.11.4 - 2023-02-12

* Fixed
  * Fix Elixir 1.15 deprecation warnings

## v0.11.3 - 2023-01-23

* Changed
  * Allow VintageNet v0.13.0 to be used

## v0.11.2 - 2023-01-16

* Fixed
  * Fix cipher flag parsing from some access points. For example, if an access
    point advertised `[WPA2-PSK+PSK-SHA256-CCMP][ESS]`, it would fail to parse
    due to "PSK" being greedily selected as the cipher instead of "PSDK-SHA256".

## v0.11.1 - 2022-07-27

* Changed
  * Added support for handling WiFi events. Currently events associated with
    WiFi AP associations are reported since they can be helpful when creating
    WiFi configuration user interfaces. More could be supported in the future.
    Thanks to @dognotdog, @THE9rtyt, and @ConnorRigby for this feature.

* Fixed
  * Remove mesh peers from reported access point lists. Mesh peers are reported
    separately and mixing them with access points was unexpected. Thanks to
    @mattludwigs for identifying and fixing the issue.

## v0.11.0 - 2022-04-30

This release requires VintageNet v0.12.0 and Elixir 1.11 or later. No external
API changes or fixes were made. Other than the new version requirements,
everything should work the same as v0.10.9.

## v0.10.9

* Changed
  * Increase `wpa_supplicant` timeout from 1 second to 4 seconds. Normally
    responses come in quickly. On GRiSP 2, initialization takes >1 second.
    This prevents an unnecessary `wpa_supplicant` restart and improves boot
    time.

## v0.10.8

* Added
  * Fall back to the wext WiFi driver interface if nl80211 doesn't work. This
    makes it possible to support the WiFi module on GRiSPv2 boards.

## v0.10.7

* Bug fixes
  * Fix crash when scanning for WiFi networks and near an Eero mesh WiFi system.

## v0.10.6

* Bug fixes
  * Fully decode WiFi flags based on inspecting the `wpa_supplicant` source
    code. This should, hopefully, fix the recurring issue with new flags being
    discovered. The flags are now decomposed into their constituent parts. The
    original flags are still present, but the new ones should be easier to
    reason about. E.g., `[:wpa2_psk_ccmp]` is now `[:wpa2_psk_ccmp, :wpa2, :psk, :ccmp]`.

## v0.10.5

* Added
  * Decode network flags that advertise WEP. Thanks to Ryota Kinukawa for this
    change.

## v0.10.4

This release only contains a build system update. It doesn't change any code and
is a safe update.

## v0.10.3

* New features
  * Support WPS PBS for connecting to access points. This is the feature where
    you press a button on the AP and "press a button" on the device to connect.
    See `VintageNetWiFi.quick_wps/1`. Thanks to @labno for this feature.

* Bug fixes
  * Added missing PSK WiFi type. Thanks again to Dömötör Gulyás for these fixes.
  * Improved handling of AP information gathering from the `wpa_supplicant`.
    This works around a rare issue seen when the `wpa_supplicant` doesn't
    respond to a BSS information request, by 1. not sending the request when the
    information is known and 2. moving info requests out of the main process to
    avoid stalling more important requests when lots of APs are around.

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

