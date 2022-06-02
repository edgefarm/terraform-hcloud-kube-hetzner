resource "null_resource" "first_control_plane" {
  connection {
    user           = "root"
    private_key    = var.ssh_private_key
    agent_identity = local.ssh_agent_identity
    host           = module.control_planes[keys(module.control_planes)[0]].ipv4_address
  }

  # Generating rke2 master config file
  provisioner "file" {
    content = yamlencode(merge({
      node-name                   = module.control_planes[keys(module.control_planes)[0]].name
      token                       = random_password.rke2_token.result
      disable-cloud-controller    = true
      disable                     = local.disable_extras
      kubelet-arg                 = ["cloud-provider=external", "volume-plugin-dir=/var/lib/kubelet/volumeplugins"]
      kube-controller-manager-arg = "flex-volume-plugin-dir=/var/lib/kubelet/volumeplugins"
      node-ip                     = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
      advertise-address           = module.control_planes[keys(module.control_planes)[0]].private_ipv4_address
      node-taint                  = local.control_plane_nodes[keys(module.control_planes)[0]].taints
      node-label                  = local.control_plane_nodes[keys(module.control_planes)[0]].labels
    }))

    destination = "/tmp/config.yaml"
  }

  # Install rke2 server
  provisioner "remote-exec" {
    inline = local.install_rke2_server
  }

  # Issue a reboot command and wait for MicroOS to reboot and be ready
  provisioner "local-exec" {
    command = <<-EOT
      ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} root@${module.control_planes[keys(module.control_planes)[0]].ipv4_address} '(sleep 2; reboot)&'; sleep 3
      until ssh ${local.ssh_args} -i /tmp/${random_string.identity_file.id} -o ConnectTimeout=2 root@${module.control_planes[keys(module.control_planes)[0]].ipv4_address} true 2> /dev/null
      do
        echo "Waiting for MicroOS to reboot and become available..."
        sleep 3
      done
    EOT
  }

  

  # Upon reboot start rke2 and wait for it to be ready to receive commands
  provisioner "remote-exec" {
    inline = [
      "systemctl start rke2-server",
      # prepare the post_install directory
      "mkdir -p /var/post_install",
      # wait for rke2 to become ready
      <<-EOT
      timeout 120 bash <<EOF
        until systemctl status rke2-server > /dev/null; do
          systemctl start rke2-server
          echo "Waiting for the rke2-server server to start..."
          sleep 2
        done
        until [ -e  ]; do
          echo "Waiting for kubectl config..."
          sleep 2
        done
        export PATH="/var/lib/rancher/rke2/bin:$PATH"
        export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"
        until [[ "\$(kubectl get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
          echo "Waiting for the cluster to become ready..."
          sleep 2
        done
      EOF
      EOT
    ]
  }

  depends_on = [
    null_resource.setup,
    hcloud_network_subnet.control_plane
  ]
}


# data "remote_file" "join_token" {
#   conn {
#     host        = module.control_planes[keys(module.control_planes)[0]].ipv4_address
#     port        = 22
#     user        = "root"
#     private_key = var.ssh_private_key
#     agent       = var.ssh_private_key == null
#   }
#   path = "/var/lib/rancher/rke2/server/token"

#   depends_on = [null_resource.first_control_plane]
# }

# This is where all the setup of Kubernetes components happen
# resource "null_resource" "kustomization" {
#   connection {
#     user           = "root"
#     private_key    = var.ssh_private_key
#     agent_identity = local.ssh_agent_identity
#     host           = module.control_planes[keys(module.control_planes)[0]].ipv4_address
#   }

#   # Upload kustomization.yaml, containing Hetzner CSI & CSM, as well as kured.
#   provisioner "file" {
#     content = yamlencode({
#       apiVersion = "kustomize.config.k8s.io/v1beta1"
#       kind       = "Kustomization"

#       resources = concat(
#         [
#           "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/${local.ccm_version}/ccm-networks.yaml",
#           "https://github.com/weaveworks/kured/releases/download/${local.kured_version}/kured-${local.kured_version}-dockerhub.yaml",
#           "https://raw.githubusercontent.com/rancher/system-upgrade-controller/master/manifests/system-upgrade-controller.yaml",
#         ],
#         var.disable_hetzner_csi ? [] : ["https://raw.githubusercontent.com/hetznercloud/csi-driver/${local.csi_version}/deploy/kubernetes/hcloud-csi.yml"],
#         var.rancher_registration_manifest_url != "" ? [var.rancher_registration_manifest_url] : []
#       ),
#       patchesStrategicMerge = concat(
#         [
#           file("${path.module}/kustomize/kured.yaml"),
#           file("${path.module}/kustomize/system-upgrade-controller.yaml"),
#           "ccm.yaml",
#         ]
#       )
#     })
#     destination = "/var/post_install/kustomization.yaml"
#   }

#   # Upload the CCM patch config
#   provisioner "file" {
#     content = templatefile(
#       "${path.module}/templates/ccm.yaml.tpl",
#       {
#         cluster_cidr_ipv4                 = local.cluster_cidr_ipv4
#         allow_scheduling_on_control_plane = local.allow_scheduling_on_control_plane
#     })
#     destination = "/var/post_install/ccm.yaml"
#   }

#   # Upload the system upgrade controller plans config
#   provisioner "file" {
#     content = templatefile(
#       "${path.module}/templates/plans.yaml.tpl",
#       {
#         channel = var.initial_rke2_channel
#     })
#     destination = "/var/post_install/plans.yaml"
#   }

#   # Deploy secrets, logging is automatically disabled due to sensitive variables
#   provisioner "remote-exec" {
#     inline = [
#       "set -ex",
#       "export \"PATH=/var/lib/rancher/rke2/bin:$PATH\"",
#       "export KUBECONFIG=\"/etc/rancher/rke2/rke2.yaml\"",
#       "kubectl -n kube-system create secret generic hcloud --from-literal=token=${var.hcloud_token} --from-literal=network=${hcloud_network.rke2.name} --dry-run=client -o yaml | kubectl apply -f -",
#       "kubectl -n kube-system create secret generic hcloud-csi --from-literal=token=${var.hcloud_token} --dry-run=client -o yaml | kubectl apply -f -",
#     ]
#   }

#   # Deploy our post-installation kustomization
#   provisioner "remote-exec" {
#     inline = concat([
#       "set -ex",

#       # This ugly hack is here, because terraform serializes the
#       # embedded yaml files with "- |2", when there is more than
#       # one yamldocument in the embedded file. Kustomize does not understand
#       # that syntax and tries to parse the blocks content as a file, resulting
#       # in weird errors. so gnu sed with funny escaping is used to
#       # replace lines like "- |3" by "- |" (yaml block syntax).
#       # due to indendation this should not changes the embedded
#       # manifests themselves
#       "sed -i 's/^- |[0-9]\\+$/- |/g' /var/post_install/kustomization.yaml",

#       "export PATH=\"/var/lib/rancher/rke2/bin:$PATH\"",
#       "export KUBECONFIG=\"/etc/rancher/rke2/rke2.yaml\"",
#       # Wait for rke2 to become ready (we check one more time) because in some edge cases, 
#       # the cluster had become unvailable for a few seconds, at this very instant.
#       <<-EOT
#       timeout 120 bash <<EOF
#         until [[ "\$(kubectl get --raw='/readyz' 2> /dev/null)" == "ok" ]]; do
#           echo "Waiting for the cluster to become ready..."
#           sleep 2
#         done
#       EOF
#       EOT
#       ,

#       # Ready, set, go for the kustomization
#       "kubectl apply -k /var/post_install",
#       "echo 'Waiting for the system-upgrade-controller deployment to become available...'",
#       "kubectl -n system-upgrade wait --for=condition=available --timeout=120s deployment/system-upgrade-controller",
#       "kubectl -n system-upgrade apply -f /var/post_install/plans.yaml"
#       ]
#     )
#   }

#   depends_on = [
#     null_resource.first_control_plane,
#     local_sensitive_file.kubeconfig,
#   ]
# }
