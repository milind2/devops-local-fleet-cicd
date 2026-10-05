resource "multipass_instance" "node_a" {
  name           = "node-a"
  image          = "24.04"
  cpus           = 2
  memory         = "4G"
  disk           = "15G"
  cloudinit_file = abspath("${path.module}/cloud-init.yaml")
}

resource "multipass_instance" "node_b" {
  name           = "node-b"
  image          = "24.04"
  cpus           = 2
  memory         = "4G"
  disk           = "15G"
  cloudinit_file = abspath("${path.module}/cloud-init.yaml")
}

output "ips" {
  value = {
    node-a = multipass_instance.node_a.ipv4
    node-b = multipass_instance.node_b.ipv4
  }
}
