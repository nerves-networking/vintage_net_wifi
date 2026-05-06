# SPDX-FileCopyrightText: 2026 Eliel A. Gordon
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.MacAddressConfigTest do
  use ExUnit.Case
  alias VintageNetWiFi.MacAddressConfig

  test "valid_mac? accepts well-formed MAC addresses" do
    assert MacAddressConfig.valid_mac?("aa:bb:cc:dd:ee:ff")
    assert MacAddressConfig.valid_mac?("AA:BB:CC:DD:EE:FF")
    assert MacAddressConfig.valid_mac?("00:11:22:33:44:55")
    assert MacAddressConfig.valid_mac?("01:23:45:67:89:Ab")
  end

  test "valid_mac? rejects malformed MAC addresses" do
    refute MacAddressConfig.valid_mac?("")
    refute MacAddressConfig.valid_mac?("aa:bb:cc:dd:ee")
    refute MacAddressConfig.valid_mac?("aa:bb:cc:dd:ee:ff:00")
    refute MacAddressConfig.valid_mac?("aa-bb-cc-dd-ee-ff")
    refute MacAddressConfig.valid_mac?("zz:bb:cc:dd:ee:ff")
    refute MacAddressConfig.valid_mac?("a:bb:cc:dd:ee:ff")
    refute MacAddressConfig.valid_mac?(:not_a_string)
    refute MacAddressConfig.valid_mac?(nil)
    refute MacAddressConfig.valid_mac?(123)
  end

  test "mfargs? recognizes {mod, fun, args} tuples" do
    assert MacAddressConfig.mfargs?({Kernel, :inspect, [:hi]})
    refute MacAddressConfig.mfargs?({Kernel, :inspect, :not_a_list})
    refute MacAddressConfig.mfargs?({"mod", :fun, []})
    refute MacAddressConfig.mfargs?("aa:bb:cc:dd:ee:ff")
    refute MacAddressConfig.mfargs?(nil)
  end

  test "resolve returns string MACs unchanged" do
    assert MacAddressConfig.resolve("aa:bb:cc:dd:ee:ff") == "aa:bb:cc:dd:ee:ff"
  end

  test "resolve applies MFArgs tuples" do
    assert MacAddressConfig.resolve({Function, :identity, ["11:22:33:44:55:66"]}) == "11:22:33:44:55:66"
  end

  test "resolve returns {:error, exception} when MFArgs raises" do
    assert {:error, %ArgumentError{}} = MacAddressConfig.resolve({String, :to_integer, ["abc"]})
  end
end
