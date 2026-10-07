
# terraform test: runs a PLAN in a temporary state; creates nothing, touches no real VM or tfstate.

run "fleet_plan" {
  command = plan # plan only, never apply

  assert {
    condition     = multipass_instance.node_a.name == "node-a" && multipass_instance.node_b.name == "node-b"
    error_message = "VMs must be named node-a and node-b (Ansible inventory and HAProxy depend on it)."
  }

  assert {
    condition     = multipass_instance.node_a.cpus == 2 && multipass_instance.node_b.cpus == 2
    error_message = "Each VM needs 2 CPUs for llama-server."
  }

  assert {
    condition     = multipass_instance.node_a.memory == "4G" && multipass_instance.node_b.memory == "4G"
    error_message = "Each VM needs 4G of memory (model + Grafana/Prometheus on node-a)."
  }

  assert {
    condition     = multipass_instance.node_a.image == "24.04" && multipass_instance.node_b.image == "24.04"
    error_message = "VMs must run Ubuntu 24.04."
  }

  assert {
    condition     = endswith(local_file.inventory.filename, "ansible/inventory.ini")
    error_message = "Inventory must be written to ansible/inventory.ini, where ansible.cfg expects it."
  }
}
