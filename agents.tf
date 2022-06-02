module "agents" {
  source = "./modules/host"

  providers = {
    hcloud = hcloud,
  }

  for_each = local.agent_nodes

  name                       = "${var.use_cluster_name_in_node_name ? "${var.cluster_name}-" : ""}${each.value.nodepool_name}"
  ssh_keys                   = [local.hcloud_ssh_key_id]
  ssh_public_key             = var.ssh_public_key
  ssh_private_key            = var.ssh_private_key
  ssh_additional_public_keys = var.ssh_additional_public_keys
  firewall_ids               = [hcloud_firewall.rke2.id]
  placement_group_id         = var.placement_group_disable ? 0 : element(hcloud_placement_group.agent.*.id, ceil(each.value.index / 10))
  location                   = each.value.location
  server_type                = each.value.server_type
  ipv4_subnet_id             = hcloud_network_subnet.agent[[for i, v in var.agent_nodepools : i if v.name == each.value.nodepool_name][0]].id
  packages_to_install        = []

  private_ipv4 = cidrhost(hcloud_network_subnet.agent[[for i, v in var.agent_nodepools : i if v.name == each.value.nodepool_name][0]].ip_range, each.value.index + 101)

  labels = {
    "provisioner" = "terraform",
    "engine"      = "rke2"
  }

  depends_on = [
    hcloud_network_subnet.agent
  ]
}

resource "null_resource" "agents" {
  for_each = local.agent_nodes

  triggers = {
    agent_id = module.agents[each.key].id
  }

  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = module.agents[each.key].ipv4_address
  }

  # Generating rke2 agent config file
  provisioner "file" {
    content = yamlencode({
      node-name     = module.agents[each.key].name
      server        = "https://${module.control_planes[keys(module.control_planes)[0]].private_ipv4_address}:9345"
      token         = random_password.rke2_token.result
      kubelet-arg   = ["cloud-provider=external", "volume-plugin-dir=/var/lib/kubelet/volumeplugins"]
      node-ip       = module.agents[each.key].private_ipv4_address
      node-label    = each.value.labels
      node-taint    = each.value.taints
    })
    destination = "/tmp/config.yaml"
  }

  # Install rke2 agent
  provisioner "remote-exec" {
    inline = local.install_rke2_agent
  }

  # Issue a reboot command and wait for MicroOS to reboot and be ready
  provisioner "local-exec" {
    command = <<-EOT
      ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} root@${module.agents[each.key].ipv4_address} '(sleep 2; reboot)&'; sleep 3
      until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} -o ConnectTimeout=2 root@${module.agents[each.key].ipv4_address} true 2> /dev/null
      do
        echo "Waiting for MicroOS to reboot and become available..."
        sleep 3
      done
    EOT
  }

  # Start the rke2 agent and wait for it to have started
  provisioner "remote-exec" {
    inline = [
      "systemctl start rke2-agent 2> /dev/null",
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status rke2-agent > /dev/null; do
          systemctl start rke2-agent 2> /dev/null
          echo "Waiting for the rke2 server to start..."
          sleep 2
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    null_resource.setup,
    null_resource.first_control_plane,
    hcloud_network_subnet.agent
  ]
}
