require "yaml"

settings = YAML.load_file(File.join(File.dirname(__FILE__), "settings.yaml"))

CONTROLLER_IP   = settings["network"]["controller_ip"]
WORKER_IP_START = settings["network"]["worker_ip_start"]
NUM_WORKERS     = settings["nodes"]["workers"]["count"]

# derive worker IPs by incrementing the last octet
IP_NW    = WORKER_IP_START.match(/^(\d+\.\d+\.\d+\.)\d+$/)[1]
IP_START = WORKER_IP_START.match(/(\d+)$/)[1].to_i

Vagrant.configure("2") do |config|
  config.vm.box = settings["software"]["box"]
  config.vm.box_check_update = false

  # Add /etc/hosts entries on every node
  config.vm.provision "shell", inline: <<-SHELL
    grep -qxF "#{CONTROLLER_IP} controller-1" /etc/hosts || echo "#{CONTROLLER_IP} controller-1" >> /etc/hosts
    #{(1..NUM_WORKERS).map { |i| "grep -qxF \"#{IP_NW}#{IP_START + i - 1} worker-#{i}\" /etc/hosts || echo \"#{IP_NW}#{IP_START + i - 1} worker-#{i}\" >> /etc/hosts" }.join("\n  ")}
  SHELL

  # Controller
  config.vm.define "controller-1" do |node|
    node.vm.hostname = "controller-1"
    node.vm.network "private_network", ip: CONTROLLER_IP
    node.vm.provider "virtualbox" do |vb|
      vb.memory = settings["nodes"]["controller"]["memory"]
      vb.cpus   = settings["nodes"]["controller"]["cpu"]
      if settings["cluster_name"] && settings["cluster_name"] != ""
        vb.customize ["modifyvm", :id, "--groups", "/#{settings["cluster_name"]}"]
      end
    end
    node.vm.provision "shell",
    env: {
      "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
    },
    path: "scripts/common.sh"
    node.vm.provision "shell",
      env: {
        "CONTROLLER_IP"    => CONTROLLER_IP,
        "WORKER_IP_START"  => WORKER_IP_START,
        "NUM_WORKERS"      => NUM_WORKERS.to_s,
        "SERVICE_CIDR"     => settings["network"]["service_cidr"],  
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
      },
      path: "scripts/certs.sh"
    node.vm.provision "shell",
      env: {
        "CONTROLLER_IP" => CONTROLLER_IP,
        "NUM_WORKERS"   => NUM_WORKERS.to_s,
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
      },
      path: "scripts/kubeconfigs.sh"

    node.vm.provision "shell",
      env: {
        "CONTROLLER_IP" => CONTROLLER_IP,
        "ETCD_VERSION"  => settings["software"]["etcd"],
      },
      path: "scripts/etcd.sh"  

    node.vm.provision "shell",
      path: "scripts/control-plane-setup.sh"

    node.vm.provision "shell",
      env: {
        "CONTROLLER_IP"      => CONTROLLER_IP,
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "SERVICE_CIDR"       => settings["network"]["service_cidr"],
      },
      path: "scripts/api-server.sh"

    node.vm.provision "shell",
      env: {
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "POD_CIDR"           => settings["network"]["pod_cidr"],
        "SERVICE_CIDR"       => settings["network"]["service_cidr"],
      },
      path: "scripts/controller-manager.sh"

    node.vm.provision "shell",
      env: {
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
      },
      path: "scripts/scheduler.sh"  
  end

  # Workers
  (1..NUM_WORKERS).each do |i|
    config.vm.define "worker-#{i}" do |node|
      node.vm.hostname = "worker-#{i}"
      node.vm.network "private_network", ip: "#{IP_NW}#{IP_START + i - 1}"
      node.vm.provider "virtualbox" do |vb|
        vb.memory = settings["nodes"]["workers"]["memory"]
        vb.cpus   = settings["nodes"]["workers"]["cpu"]
        if settings["cluster_name"] && settings["cluster_name"] != ""
          vb.customize ["modifyvm", :id, "--groups", "/#{settings["cluster_name"]}"]
        end
      end
      node.vm.provision "shell", 
      env: {
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
      },
      path: "scripts/common.sh"
    end
  end
end