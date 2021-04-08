# -*- mode: ruby -*-
# vi: set ft=ruby :

ERLANG_VERSION="23.3"
ELIXIR_VERSION="1.11.4-otp-23"
VM_MEMORY=2048
VM_CORES=1

Vagrant.configure("2") do |config|

  config.vm.box = "generic/ubuntu2010"

  config.vm.provider :vmware_fusion do |v, override|
    v.vmx['memsize'] = VM_MEMORY
    v.vmx['numvcpus'] = VM_CORES
  end

  config.vm.provider :virtualbox do |v, override|
    v.memory = VM_MEMORY
    v.cpus = VM_CORES

    required_plugins = %w( vagrant-vbguest )
    required_plugins.each do |plugin|
      system "vagrant plugin install #{plugin}" unless Vagrant.has_plugin? plugin
    end
  end

  config.vm.provision 'shell' do |s|
    s.inline = 'echo Setting up machine name'

    config.vm.provider :vmware_fusion do |v, override|
      v.vmx['displayname'] = "vintage_net_wifi"
    end

    config.vm.provider :virtualbox do |v, override|
      v.name = "vintage_net_wifi"
    end
  end

  config.vm.provision 'shell', privileged: true, inline: <<-SHELL
    apt-get -q update
    apt-get purge -q -y snapd lxcfs lxd ubuntu-core-launcher snap-confine
    apt-get -q -y install build-essential libncurses5-dev \
      git unzip bc autoconf m4 libssh-dev libmnl-dev libnl-genl-3-dev \
      pkg-config wpasupplicant hostapd wireless-tools dnsmasq

    apt-get -q -y autoremove
    apt-get -q -y clean
    update-locale LC_ALL=en_US.UTF-8
    ln -sf /bin/busybox /usr/bin/udhcpc
    ln -sf /bin/busybox /usr/bin/udhcpd
    systemctl disable dnsmasq
    SHELL

  config.vm.provision 'shell', privileged: true, inline: <<-SHELL
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.8.0
    echo ". $HOME/.asdf/asdf.sh" >> ~/.bashrc
    echo ". $HOME/.asdf/completions/asdf.bash" >> ~/.bashrc
    . $HOME/.asdf/asdf.sh
    asdf plugin-add erlang
    asdf plugin-add elixir
    asdf install erlang #{ERLANG_VERSION}
    asdf global erlang #{ERLANG_VERSION}
    asdf install elixir #{ELIXIR_VERSION}
    asdf global elixir #{ELIXIR_VERSION}
    mix local.hex --force
    git clone https://github.com/oblique/create_ap.git ~/create_ap
    make -C ~/create_ap install
    SHELL

  # Re-enable synced folders
  config.vm.synced_folder ".", "/vagrant"
end
