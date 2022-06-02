
data "remote_file" "kubeconfig" {
  conn {
    host        = module.control_planes[keys(module.control_planes)[0]].ipv4_address
    port        = 22
    user        = "root"
    private_key = var.ssh_private_key
    agent       = var.ssh_private_key == null
  }
  path = "/etc/rancher/rke2/rke2.yaml"

  depends_on = [null_resource.control_planes[0]]
}

locals {
  kubeconfig_external = replace(data.remote_file.kubeconfig.content, "127.0.0.1", module.control_planes[keys(module.control_planes)[0]].ipv4_address)
  # kubeconfig_parsed   = yamldecode(local.kubeconfig_external)
  # kubeconfig_data = {
  #   host                   = local.kubeconfig_parsed["clusters"][0]["cluster"]["server"]
  #   client_certificate     = base64decode(local.kubeconfig_parsed["users"][0]["user"]["client-certificate-data"])
  #   client_key             = base64decode(local.kubeconfig_parsed["users"][0]["user"]["client-key-data"])
  #   cluster_ca_certificate = base64decode(local.kubeconfig_parsed["clusters"][0]["cluster"]["certificate-authority-data"])
  # }
}

resource "local_sensitive_file" "kubeconfig" {
  content         = local.kubeconfig_external
  filename        = "${var.cluster_name}_kubeconfig.yaml"
  file_permission = "600"
}
