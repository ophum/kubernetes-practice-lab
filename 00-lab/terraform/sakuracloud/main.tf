locals {
  lab_wireguard_cidr = "10.0.0.0/24"
  lab_cidr           = cidrsubnet("192.168.0.0/24", 4, 0)
}

resource "sakuracloud_switch" "k8s-lab-switch0" {
  name = "k8s-lab-switch0"
}

resource "sakuracloud_vpc_router" "k8s-lab-router" {
  name                = "k8s-lab-router"
  tags                = []
  internet_connection = true

  private_network_interface {
    index        = 1
    switch_id    = sakuracloud_switch.k8s-lab-switch0.id
    ip_addresses = [cidrhost(local.lab_cidr, 1)]
    netmask      = 24
  }

  wire_guard {
    ip_address = format("%s/%d", cidrhost(local.lab_wireguard_cidr, 1), 24)

    dynamic "peer" {
      for_each = { for i, v in var.wireguard_peers : i => v }

      content {
        name = peer.value.name
        # for_eachのkeyが0スタート
        # wireguardのIPが10.0.0.1なので2から始まるように+2する
        ip_address = cidrhost(local.lab_wireguard_cidr, peer.key + 2)
        public_key = peer.value.public_key
      }
    }
  }
}
