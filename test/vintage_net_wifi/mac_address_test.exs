# SPDX-FileCopyrightText: 2026 Eliel A. Gordon
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.MacAddressTest do
  use ExUnit.Case
  alias VintageNetWiFi.MacAddress

  test "valid? accepts well-formed MAC addresses" do
    assert MacAddress.valid?("aa:bb:cc:dd:ee:ff")
    assert MacAddress.valid?("AA:BB:CC:DD:EE:FF")
    assert MacAddress.valid?("00:11:22:33:44:55")
    assert MacAddress.valid?("01:23:45:67:89:Ab")
  end

  test "valid? rejects malformed MAC addresses" do
    refute MacAddress.valid?("")
    refute MacAddress.valid?("aa:bb:cc:dd:ee")
    refute MacAddress.valid?("aa:bb:cc:dd:ee:ff:00")
    refute MacAddress.valid?("aa-bb-cc-dd-ee-ff")
    refute MacAddress.valid?("zz:bb:cc:dd:ee:ff")
    refute MacAddress.valid?("a:bb:cc:dd:ee:ff")
    refute MacAddress.valid?(:not_a_string)
    refute MacAddress.valid?(nil)
    refute MacAddress.valid?(123)
  end
end
