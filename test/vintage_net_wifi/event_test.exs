# SPDX-FileCopyrightText: 2021 Dömötör Gulyás
# SPDX-FileCopyrightText: 2022 Connor Rigby
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetWiFi.EventTest do
  use ExUnit.Case
  alias VintageNetWiFi.Event

  doctest Event

  test "create CTRL-EVENT-ASSOC-REJECT" do
    assert Event.new(
             "CTRL-EVENT-ASSOC-REJECT",
             %{"bssid" => "ab:cd:ef:01:02:03", "status_code" => "1"}
           ) == %Event{
             name: "CTRL-EVENT-ASSOC-REJECT",
             bssid: "ab:cd:ef:01:02:03",
             status_code: 1
           }
  end

  test "create CTRL-EVENT-SSID-TEMP-DISABLED" do
    assert Event.new(
             "CTRL-EVENT-SSID-TEMP-DISABLED",
             %{
               "id" => "0",
               "ssid" => "abcdef010203",
               "auth_failures" => "1",
               "duration" => "10",
               "reason" => "CONN_FAILED"
             }
           ) == %Event{
             name: "CTRL-EVENT-SSID-TEMP-DISABLED",
             id: 0,
             ssid: "abcdef010203",
             auth_failures: 1,
             duration: 10,
             reason: "CONN_FAILED"
           }
  end

  test "create CTRL-EVENT-SSID-REENABLED" do
    assert Event.new(
             "CTRL-EVENT-SSID-REENABLED",
             %{"id" => "0", "ssid" => "abcdef010203"}
           ) == %Event{
             name: "CTRL-EVENT-SSID-REENABLED",
             id: 0,
             ssid: "abcdef010203"
           }
  end
end
