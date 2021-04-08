import Config

if Mix.env() == :hwsim do
  config :vintage_net,
    resolvconf: "/tmp/vintage_net/resolv.conf",
    persistence_dir: "./tmp/vintage_net/persistence"

  config :logger, backends: [RingLogger]
  config :logger, RingLogger, max_size: 2000
else
  # Overrides for unit tests:
  #
  # * resolvconf: don't update the real resolv.conf
  # * persistence_dir: use the current directory
  config :vintage_net,
    resolvconf: "/tmp/vintage_net/resolv.conf",
    persistence_dir: "./tmp/vintage_net/persistence",
    path: "#{File.cwd!()}/test/fixtures/root/bin"
end
