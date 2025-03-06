# SPDX-FileCopyrightText: 2019 Frank Hunleth
# SPDX-FileCopyrightText: 2020 Matt Ludwigs
#
# SPDX-License-Identifier: Apache-2.0
#
import Config

# Overrides for unit tests:
#
# * resolvconf: don't update the real resolv.conf
# * persistence_dir: use the current directory
config :vintage_net,
  resolvconf: "/dev/null",
  persistence_dir: "./test_tmp/persistence",
  path: "#{File.cwd!()}/test/fixtures/root/bin"
