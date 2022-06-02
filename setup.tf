resource "random_string" "identity_file" {
  length  = 20
  lower   = true
  special = false
  number  = true
  upper   = false
}

resource "null_resource" "setup" {
  # Prepare ssh identity file 
  provisioner "local-exec" {
    command = <<-EOT
      install -b -m 600 /dev/null /tmp/${random_string.identity_file.id}
      echo "${local.ssh_client_identity}" > /tmp/${random_string.identity_file.id}
    EOT
  }
}

resource "null_resource" "teardown" {
  # Cleanup ssh identity file 
  provisioner "local-exec" {
    command = <<-EOT
      rm /tmp/${random_string.identity_file.id}
    EOT
  }
  
  depends_on = [
    null_resource.first_control_plane,
    null_resource.control_planes,
    null_resource.agents,
    # null_resource.kustomization
  ]
}

