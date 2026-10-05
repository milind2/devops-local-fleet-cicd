resource "local_file" "inventory" {
  filename        = abspath("${path.module}/../ansible/inventory.ini")
  file_permission = "0644"
  content         = <<-INI
    [llama]
    node-a ansible_host=${multipass_instance.node_a.ipv4}
    node-b ansible_host=${multipass_instance.node_b.ipv4}

    [lb]
    node-a

    [monitoring]
    node-a

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/fleet_key
    ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
  INI
}
