defmodule VintageNetWiFi.WPASupplicantLLTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias VintageNetWiFi.WPASupplicantLL
  alias VintageNetWiFiTest.MockWPASupplicant

  setup do
    socket_path = "test_tmp/tmp_wpa_supplicant_socket"
    mock = start_supervised!({MockWPASupplicant, socket_path})

    on_exit(fn ->
      _ = File.rm(socket_path)
      _ = File.rm(socket_path <> ".ex")
    end)

    {:ok, socket_path: socket_path, mock: mock}
  end

  test "receives notifications", context do
    start_supervised!({WPASupplicantLL, path: context.socket_path, notification_pid: self()})

    MockWPASupplicant.send_message(context.mock, "<1>Hello")
    MockWPASupplicant.send_message(context.mock, "<2>Goodbye")

    assert_receive {VintageNetWiFi.WPASupplicantLL, 1, "Hello"}
    assert_receive {VintageNetWiFi.WPASupplicantLL, 2, "Goodbye"}
  end

  test "responds to requests", context do
    ll = start_supervised!({WPASupplicantLL, path: context.socket_path, notification_pid: self()})

    MockWPASupplicant.set_responses(context.mock, %{"SCAN" => "OK"})

    assert {:ok, "OK"} = WPASupplicantLL.control_request(ll, "SCAN")
  end

  test "ignores unexpected responses", context do
    # capture_log hides the "log message from WPASupplicantLL when it sees an unexpected message"
    capture_log(fn ->
      ll =
        start_supervised!({WPASupplicantLL, path: context.socket_path, notification_pid: self()})

      MockWPASupplicant.send_message(context.mock, "Bad response")

      # Wait a bit here and simultaneously make sure we don't get a notification
      refute_receive {VintageNetWiFi.WPASupplicantLL, _priority, _message}

      # If WPASupplicantLL crashes, this will fail. Remove capture_log and look at the log messages.
      assert Process.alive?(ll)
    end)
  end

  test "handles notifications while waiting for a response", context do
    ll = start_supervised!({WPASupplicantLL, path: context.socket_path, notification_pid: self()})

    MockWPASupplicant.set_responses(context.mock, %{"SCAN" => ["<1>Notification", "OK"]})

    assert {:ok, "OK"} = WPASupplicantLL.control_request(ll, "SCAN")
    assert_receive {VintageNetWiFi.WPASupplicantLL, 1, "Notification"}
    assert MockWPASupplicant.get_requests(context.mock) == ["SCAN"]
  end

  test "multiple requests outstanding", context do
    ll = start_supervised!({WPASupplicantLL, path: context.socket_path, notification_pid: self()})

    # The intention here is to start up enough processes to exercise
    # the multiple request outstanding code since it's currently not written
    # to make this easy to test.
    process_count = 100

    responses = for i <- 1..process_count, into: %{}, do: {"REQUEST#{i}", "OK#{i}"}

    MockWPASupplicant.set_responses(context.mock, responses)
    main_process = self()

    for i <- 1..process_count do
      spawn(fn ->
        request = "REQUEST#{i}"
        expected = "OK#{i}"
        assert {:ok, expected} == WPASupplicantLL.control_request(ll, request)
        send(main_process, "DONE#{i}")
      end)
    end

    # Wait for everything to complete
    for i <- 1..process_count do
      expected = "DONE#{i}"
      assert_receive ^expected, 5_000
    end
  end
end
