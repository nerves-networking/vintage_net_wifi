defmodule VintageNetWiFiTest.Utils do
  @moduledoc false

  @spec default_opts() :: keyword()
  def default_opts() do
    # Use the defaults in mix.exs, but normalize the paths to commands
    Application.get_all_env(:vintage_net)
  end

  @spec udhcpc_child_spec(VintageNet.ifname(), String.t()) :: Supervisor.child_spec()
  def udhcpc_child_spec(ifname, hostname) do
    beam_notify = Application.app_dir(:beam_notify, "priv/beam_notify")
    env = BEAMNotify.env(name: "vintage_net_comm", report_env: true)

    %{
      id: :udhcpc,
      start: {
        VintageNet.Interface.IfupDaemon,
        :start_link,
        [
          [
            ifname: ifname,
            command: "udhcpc",
            args: [
              "-f",
              "-i",
              ifname,
              "-x",
              "hostname:#{hostname}",
              "-s",
              beam_notify
            ],
            opts: [
              stderr_to_stdout: true,
              log_output: :debug,
              log_prefix: "udhcpc(#{ifname}): ",
              env: env
            ]
          ]
        ]
      }
    }
  end

  @spec udhcpd_child_spec(VintageNet.ifname()) :: Supervisor.child_spec()
  def udhcpd_child_spec(ifname) do
    env = BEAMNotify.env(name: "vintage_net_comm", report_env: true)

    %{
      id: :udhcpd,
      restart: :permanent,
      shutdown: 500,
      start:
        {MuonTrap.Daemon, :start_link,
         [
           "udhcpd",
           [
             "-f",
             "/tmp/vintage_net/udhcpd.conf.#{ifname}"
           ],
           [stderr_to_stdout: true, log_output: :debug, env: env]
         ]},
      type: :worker
    }
  end
end
