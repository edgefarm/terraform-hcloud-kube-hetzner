resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

resource "hcloud_ssh_key" "rke2" {
  count      = var.hcloud_ssh_key_id == null ? 1 : 0
  name       = var.cluster_name
  public_key = var.ssh_public_key
}

resource "hcloud_network" "rke2" {
  name     = var.cluster_name
  ip_range = local.network_ipv4_cidr
}

# We start from the end of the subnets cird array, 
# as we would have fewer control plane nodepools, than angent ones.
resource "hcloud_network_subnet" "control_plane" {
  count        = length(var.control_plane_nodepools)
  network_id   = hcloud_network.rke2.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[255 - count.index]
}

# Here we start at the beginning of the subnets cird array
resource "hcloud_network_subnet" "agent" {
  count        = length(var.agent_nodepools)
  network_id   = hcloud_network.rke2.id
  type         = "cloud"
  network_zone = var.network_region
  ip_range     = local.network_ipv4_subnets[count.index]
}

resource "hcloud_firewall" "rke2" {
  name = var.cluster_name

  dynamic "rule" {
    for_each = concat(local.base_firewall_rules, var.extra_firewall_rules)
    content {
      direction       = rule.value.direction
      protocol        = rule.value.protocol
      port            = lookup(rule.value, "port", null)
      destination_ips = lookup(rule.value, "destination_ips", [])
      source_ips      = lookup(rule.value, "source_ips", [])
    }
  }
}

resource "hcloud_placement_group" "control_plane" {
  count = ceil(local.control_plane_count / 10)
  name  = "${var.cluster_name}-control-plane-${count.index + 1}"
  type  = "spread"
}

resource "hcloud_placement_group" "agent" {
  count = ceil(local.agent_count / 10)
  name  = "${var.cluster_name}-agent-${count.index + 1}"
  type  = "spread"
}

# data "hcloud_load_balancer" "ingress-nginx" {
#   count = 1
#   name  = "${var.cluster_name}-ingress-nginx"

#   depends_on = [null_resource.kustomization]
# }
