defmodule VintageNetWiFi.WPASupplicant do
  use GenServer

  alias VintageNet.Interface.EAPStatus
  alias VintageNetWiFi.{WPASupplicantDecoder, WPASupplicantLL}
  require Logger

  @moduledoc """
  Control a wpa_supplicant instance for an interface.
  """

  @doc """
  Start a GenServer to manage communication with a wpa_supplicant

  Arguments:

  * `:wpa_supplicant - the path to the wpa_supplicant binary
  * `:wpa_supplicant_conf_path - the path to the supplicant's conf file
  * `:ifname` - the network interface
  * `:control_path` - the path to the wpa_supplicant control file
  * `:keep_alive_interval` - how often to ping the wpa_supplicant to
    make sure it's still alive (defaults to 60,000 seconds)
  * `:ap_mode` - true if the WiFi module and wpa_supplicant are
    in access point mode
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args) do
    ifname = Keyword.fetch!(args, :ifname)
    GenServer.start_link(__MODULE__, args, name: via_name(ifname))
  end

  defp via_name(ifname) do
    {:via, Registry, {VintageNet.Interface.Registry, {__MODULE__, ifname}}}
  end

  @doc """
  Initiate a scan of WiFi networks
  """
  @spec scan(VintageNet.ifname()) :: :ok
  def scan(ifname) do
    GenServer.call(via_name(ifname), :scan)
  end

  @doc """
  Polls for signal level info
  """
  @spec signal_poll(VintageNet.ifname()) :: {:ok, any()} | {:error, any()}
  def signal_poll(ifname) do
    GenServer.call(via_name(ifname), :signal_poll)
  end

  @impl true
  def init(args) do
    wpa_supplicant = Keyword.fetch!(args, :wpa_supplicant)
    wpa_supplicant_conf_path = Keyword.fetch!(args, :wpa_supplicant_conf_path)

    control_dir = Keyword.fetch!(args, :control_path)
    ifname = Keyword.fetch!(args, :ifname)
    keep_alive_interval = Keyword.get(args, :keep_alive_interval, 60000)
    ap_mode = Keyword.get(args, :ap_mode, false)
    verbose = Keyword.get(args, :verbose, false)

    state = %{
      wpa_supplicant: wpa_supplicant,
      wpa_supplicant_conf_path: wpa_supplicant_conf_path,
      control_dir: control_dir,
      keep_alive_interval: keep_alive_interval,
      ifname: ifname,
      ap_mode: ap_mode,
      verbose: verbose,
      access_points: %{},
      clients: [],
      peers: [],
      current_ap: nil,
      eap_status: %EAPStatus{},
      ll: nil
    }

    {:ok, state, {:continue, :continue}}
  end

  @impl true
  def handle_continue(:continue, state) do
    # The control file paths depend whether the config uses AP mode and whether
    # the driver has a separate P2P interface. We find out based on which
    # control files appear.
    control_paths = get_control_paths(state)

    # Start the supplicant
    {:ok, _supplicant} =
      if state.wpa_supplicant != "" do
        # FIXME: This appears to be needed when restarting the wpa_supplicant.
        # It is an imperfect fix to an issue when running AP mode. Sometimes
        # AP mode would look like it came up, but you couldn't connect to it.
        # VintageNet.info reports that the interface is disconnected.
        Process.sleep(1000)

        # Erase old old control paths just in case they exist
        Enum.each(control_paths, &File.rm/1)

        verbose_flag = if state.verbose, do: ["-dd"], else: []

        MuonTrap.Daemon.start_link(
          state.wpa_supplicant,
          ["-i", state.ifname, "-c", state.wpa_supplicant_conf_path | verbose_flag],
          VintageNet.Command.add_muon_options(stderr_to_stdout: true, log_output: :debug)
        )
      else
        # No wpa_supplicant. The assumption is that someone else started it.
        # Currently this is only for unit tests.
        {:ok, nil}
      end

    # Wait for the wpa_supplicant to create its control files.
    primary_path =
      case wait_for_control_file(control_paths) do
        [primary_path, secondary_path] ->
          {:ok, secondary_ll} = WPASupplicantLL.start_link(secondary_path)
          :ok = WPASupplicantLL.subscribe(secondary_ll)
          {:ok, "OK\n"} = WPASupplicantLL.control_request(secondary_ll, "ATTACH")
          primary_path

        [primary_path] ->
          primary_path

        _ ->
          raise RuntimeError,
                "Couldn't find wpa_supplicant control files: #{inspect(control_paths)}"
      end

    {:ok, ll} = WPASupplicantLL.start_link(primary_path)
    :ok = WPASupplicantLL.subscribe(ll)
    {:ok, "OK\n"} = WPASupplicantLL.control_request(ll, "ATTACH")

    # Refresh the AP list
    access_points = get_access_points(ll)

    new_state = %{state | access_points: access_points, ll: ll}

    # Make sure that the property table is in sync with our state
    update_access_points_property(new_state)
    update_clients_property(new_state)

    {:noreply, new_state, state.keep_alive_interval}
  end

  @impl true
  def handle_call(:scan, _from, %{ap_mode: true} = state) do
    # When in AP mode, scans need to be forced so that they work.
    # The wpa_supplicant won't set the appropriate flag to make
    # this happen, so call a C program to do it.

    force_ap_scan = Application.app_dir(:vintage_net_wifi, ["priv", "force_ap_scan"])

    case System.cmd(force_ap_scan, [state.ifname]) do
      {_output, 0} ->
        {:reply, :ok, state}

      {_output, _nonzero} ->
        {:reply, {:error, "force_ap_scan failed"}, state}
    end
  end

  @impl true
  def handle_call(:scan, _from, state) do
    response =
      case WPASupplicantLL.control_request(state.ll, "SCAN") do
        {:ok, <<"OK", _rest::binary>>} -> :ok
        {:ok, something_else} -> {:error, String.trim(something_else)}
        error -> error
      end

    {:reply, response, state}
  end

  @impl true
  def handle_call(:signal_poll, _from, state) do
    response = get_signal_info(state.ll)
    {:reply, response, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    case WPASupplicantLL.control_request(state.ll, "PING") do
      {:ok, <<"PONG", _rest::binary>>} ->
        {:noreply, state, state.keep_alive_interval}

      other ->
        raise "Bad PING response: #{inspect(other)}"
    end
  end

  @impl true
  def handle_info({VintageNetWiFi.WPASupplicantLL, _priority, message}, state) do
    notification = WPASupplicantDecoder.decode_notification(message)

    new_state = handle_notification(notification, state)
    {:noreply, new_state, new_state.keep_alive_interval}
  end

  defp handle_notification({:event, "CTRL-EVENT-SCAN-RESULTS"}, state) do
    # Collect all of the access points
    access_points = get_access_points(state.ll)
    new_state = %{state | access_points: access_points}

    update_access_points_property(new_state)

    new_state
  end

  defp handle_notification({:event, "CTRL-EVENT-BSS-ADDED", _index, bssid}, state) do
    case get_access_point_info(state.ll, bssid) do
      {:ok, ap} ->
        access_points = Map.put(state.access_points, ap.bssid, ap)
        new_state = %{state | access_points: access_points}
        update_access_points_property(new_state)
        new_state

      _error ->
        Logger.warn("AP added and then removed before we could get info on it: #{bssid}")
        state
    end
  end

  defp handle_notification({:event, "CTRL-EVENT-BSS-REMOVED", _index, bssid}, state) do
    access_points = Map.delete(state.access_points, bssid)
    new_state = %{state | access_points: access_points}
    update_access_points_property(new_state)
    new_state
  end

  # Ignored
  defp handle_notification({:event, "CTRL-EVENT-SCAN-STARTED"}, state), do: state

  defp handle_notification({:event, "AP-STA-CONNECTED", client}, state) do
    if client in state.clients do
      state
    else
      clients = [client | state.clients]
      new_state = %{state | clients: clients}
      update_clients_property(new_state)
      new_state
    end
  end

  defp handle_notification({:event, "AP-STA-DISCONNECTED", client}, state) do
    clients = List.delete(state.clients, client)
    new_state = %{state | clients: clients}
    update_clients_property(new_state)
    new_state
  end

  defp handle_notification({:event, "CTRL-EVENT-CONNECTED", bssid, "completed", _}, state) do
    Logger.info("Connected to AP: #{bssid}")

    case get_access_point_info(state.ll, bssid) do
      {:ok, ap} ->
        new_state = %{state | current_ap: ap}
        update_current_access_point_property(new_state)
        new_state

      _error ->
        Logger.warn("Connected and disconnected to AP before we could get info on it: #{bssid}")

        new_state = %{state | current_ap: nil}
        update_current_access_point_property(new_state)
        new_state
    end
  end

  defp handle_notification({:event, "CTRL-EVENT-CONNECTED", bssid, status, _}, state) do
    Logger.warn("Unknown AP connection status: #{bssid} #{status}")
    new_state = %{state | current_ap: nil}
    update_current_access_point_property(new_state)
    new_state
  end

  defp handle_notification({:event, "CTRL-EVENT-DISCONNECTED", bssid, _}, state) do
    Logger.warn("AP disconnected: #{bssid}")
    new_state = %{state | current_ap: nil}
    update_current_access_point_property(new_state)
    new_state
  end

  defp handle_notification({:event, "CTRL-EVENT-EAP-STATUS", %{"status" => "started"}}, state) do
    new_state = %{
      state
      | eap_status: %{state.eap_status | status: :started, timestamp: DateTime.utc_now()}
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-STATUS",
          %{"parameter" => method, "status" => "accept proposed method"}},
         state
       ) do
    new_state = %{
      state
      | eap_status: %{state.eap_status | method: method, timestamp: DateTime.utc_now()}
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-STATUS",
          %{"parameter" => "success", "status" => "remote certificate verification"}},
         state
       ) do
    new_state = %{
      state
      | eap_status: %{
          state.eap_status
          | remote_certificate_verified?: true,
            timestamp: DateTime.utc_now()
        }
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-STATUS",
          %{"parameter" => "failure", "status" => "remote certificate verification"}},
         state
       ) do
    new_state = %{
      state
      | eap_status: %{
          state.eap_status
          | remote_certificate_verified?: false,
            timestamp: DateTime.utc_now()
        }
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-STATUS", %{"parameter" => "failure", "status" => "completion"}},
         state
       ) do
    new_state = %{
      state
      | eap_status: %{state.eap_status | status: :failure, timestamp: DateTime.utc_now()}
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-STATUS", %{"parameter" => "success", "status" => "completion"}},
         state
       ) do
    new_state = %{
      state
      | eap_status: %{state.eap_status | status: :success, timestamp: DateTime.utc_now()}
    }

    update_eap_status_property(new_state)
    new_state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-PEER-CERT",
          %{"cert" => _cert, "depth" => _depth, "subject" => _subject}},
         state
       ) do
    # TODO(Connor) - store cert on the eap-status
    state
  end

  defp handle_notification(
         {:event, "CTRL-EVENT-EAP-PEER-CERT",
          %{"hash" => _hash, "depth" => _depth, "subject" => _subject}},
         state
       ) do
    # TODO(Connor) - store cert on the eap-status
    state
  end

  defp handle_notification({:event, "MESH-PEER-CONNECTED", peer}, state) do
    case get_access_point_info(state.ll, peer) do
      {:ok, peer} ->
        peers = [peer | state.peers]
        new_state = %{state | peers: peers}
        update_peers_property(new_state)
        new_state

      {:error, reason} ->
        _ = Logger.error("Failed to get information about mesh peer: #{peer} #{inspect(reason)}")
        state
    end
  end

  defp handle_notification({:event, "MESH-PEER-DISCONNECTED", peer}, state) do
    peers =
      Enum.reject(state.peers, fn
        %{bssid: ^peer} -> true
        _ -> false
      end)

    new_state = %{state | peers: peers}
    update_peers_property(new_state)
    new_state
  end

  defp handle_notification({:event, "CTRL-EVENT-TERMINATING"}, _state) do
    # This really shouldn't happen. The only way I know how to cause this
    # is to send a SIGTERM to the wpa_supplicant.
    exit(:wpa_supplicant_terminated)
  end

  defp handle_notification({:info, message}, state) do
    Logger.info("wpa_supplicant(#{state.ifname}): #{message}")
    state
  end

  defp handle_notification(unhandled, state) do
    Logger.info("WPASupplicant ignoring #{inspect(unhandled)}")
    state
  end

  defp get_signal_info(ll) do
    with {:ok, raw_response} <- WPASupplicantLL.control_request(ll, "SIGNAL_POLL") do
      case raw_response do
        <<"FAIL", _rest::binary>> ->
          {:error, "FAIL"}

        _ ->
          case WPASupplicantDecoder.decode_kv_response(raw_response) do
            empty when empty == %{} ->
              {:error, :unknown}

            response ->
              center_frequency1 = response["CENTER_FRQ1"] |> String.to_integer(10)

              center_frequency2 =
                if response["CENTER_FRQ2"] != nil,
                  do: response["CENTER_FRQ2"] |> String.to_integer(10),
                  else: 0

              frequency = response["FREQUENCY"] |> String.to_integer(10)
              linkspeed = response["LINKSPEED"] |> String.to_integer(10)
              signal_dbm = response["RSSI"] |> String.to_integer(10)
              width = response["WIDTH"]

              signal_info =
                VintageNetWiFi.SignalInfo.new(
                  center_frequency1,
                  center_frequency2,
                  frequency,
                  linkspeed,
                  signal_dbm,
                  width
                )

              {:ok, signal_info}
          end
      end
    end
  end

  defp get_access_points(ll) do
    get_access_points(ll, 0, %{})
  end

  defp get_access_points(ll, index, acc) do
    case get_access_point_info(ll, index) do
      {:ok, ap} ->
        get_access_points(ll, index + 1, Map.put(acc, ap.bssid, ap))

      _error ->
        acc
    end
  end

  defp get_access_point_info(ll, index_or_bssid) do
    with {:ok, raw_response} <- WPASupplicantLL.control_request(ll, "BSS #{index_or_bssid}") do
      case WPASupplicantDecoder.decode_kv_response(raw_response) do
        empty when empty == %{} ->
          {:error, :unknown}

        %{"mesh_id" => _} = mesh_response ->
          peer = VintageNetWiFi.MeshPeer.new(mesh_response)
          {:ok, peer}

        response ->
          frequency = String.to_integer(response["freq"])
          signal_dbm = String.to_integer(response["level"])
          flags = WPASupplicantDecoder.parse_flags(response["flags"])
          ssid = response["ssid"]
          bssid = response["bssid"]

          ap = VintageNetWiFi.AccessPoint.new(bssid, ssid, frequency, signal_dbm, flags)
          {:ok, ap}
      end
    end
  end

  defp update_access_points_property(state) do
    ap_list = Map.values(state.access_points)

    VintageNet.PropertyTable.put(
      VintageNet,
      ["interface", state.ifname, "wifi", "access_points"],
      ap_list
    )
  end

  defp update_clients_property(state) do
    VintageNet.PropertyTable.put(
      VintageNet,
      ["interface", state.ifname, "wifi", "clients"],
      state.clients
    )
  end

  defp update_peers_property(state) do
    VintageNet.PropertyTable.put(
      VintageNet,
      ["interface", state.ifname, "wifi", "peers"],
      state.peers
    )
  end

  defp update_current_access_point_property(state) do
    VintageNet.PropertyTable.put(
      VintageNet,
      ["interface", state.ifname, "wifi", "current_ap"],
      state.current_ap
    )
  end

  defp update_eap_status_property(state) do
    VintageNet.PropertyTable.put(
      VintageNet,
      ["interface", state.ifname, "eap_status"],
      state.eap_status
    )
  end

  defp get_control_paths(%{control_dir: dir, ap_mode: true, ifname: ifname} = _state) do
    [Path.join(dir, "p2p-dev-#{ifname}"), Path.join(dir, ifname)]
  end

  defp get_control_paths(%{control_dir: dir, ifname: ifname}) do
    [Path.join(dir, ifname)]
  end

  defp wait_for_control_file(paths, time_left \\ 3000)

  defp wait_for_control_file(_paths, time_left) when time_left <= 0 do
    []
  end

  defp wait_for_control_file(paths, time_left) do
    case Enum.filter(paths, &File.exists?/1) do
      [] ->
        Process.sleep(250)
        wait_for_control_file(paths, time_left - 250)

      found_paths when length(found_paths) < length(paths) ->
        # I don't think that it's guaranteed that all paths are always created,
        # so all this to work, but with a penalty just in case the others show
        # up momentarily.
        Process.sleep(100)
        Enum.filter(paths, &File.exists?/1)

      found_paths ->
        found_paths
    end
  end
end
