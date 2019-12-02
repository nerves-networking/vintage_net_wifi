use Mix.Config

# Overrides for unit tests:
#
# * resolvconf: don't update the real resolv.conf
# * persistence_dir: use the current directory
# * bin_ip: just fail if anything calls ip rather that run it
config :vintage_net,
  resolvconf: "/dev/null",
  persistence_dir: "./test_tmp/persistence",
  bin_ip: "false"
