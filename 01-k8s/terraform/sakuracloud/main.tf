locals {
  lab_wireguard_cidr     = "10.0.0.0/24"
  lab_cidr               = "172.31.0.0/16"
  lab_common_cidr        = "172.31.0.0/24"
  lab_gateway_ip_address = "172.31.0.1"
}


locals {
  k8s_cidr         = cidrsubnet(local.lab_cidr, 8, 1)
  k8s_cplane_count = 3
  k8s_node_count   = 3
}

locals {
  k8s_common_cidr = cidrsubnet(local.k8s_cidr, 4, 1)
  k8s_cplane_cidr = cidrsubnet(local.k8s_cidr, 4, 2)
  k8s_node_cidr   = cidrsubnet(local.k8s_cidr, 4, 3)
}

locals {
  k8s_lb = {
    ip_address = cidrhost(local.k8s_common_cidr, 1)
    cplane_vip = cidrhost(local.k8s_common_cidr, 2)
  }
}

# lab 
data "sakuracloud_switch" "k8s-lab-switch0" {
  filter {
    names = ["k8s-lab-switch0"]
  }
}

data "sakuracloud_ssh_key" "initial" {
  filter {
    names = ["ophum-ssh-key"]
  }
}


# archive
data "sakuracloud_archive" "ubuntu" {
  filter {
    tags = ["cloud-init", "distro-ubuntu", "distro-ver-22.04.3"]
  }
}

# dns
data "sakuracloud_dns" "domain_zone" {
  filter {
    names = [var.domain_zone]
  }
}

resource "sakuracloud_dns_record" "k8s-cplane-lb" {
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = "cplane.k8s-01"
  type   = "A"
  ttl    = 60
  value  = local.k8s_lb.ip_address
}

resource "sakuracloud_dns_record" "k8s-cplane" {
  count  = local.k8s_cplane_count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("cplane-%02d.k8s-01", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.k8s_cplane_cidr, count.index + 1)
}

resource "sakuracloud_dns_record" "k8s-node" {
  count  = local.k8s_node_count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("node-%02d.k8s-01", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.k8s_node_cidr, count.index + 1)
}

#
# cplane setup
#
resource "sakuracloud_disk" "k8s-cplane" {
  count             = local.k8s_cplane_count
  name              = format("cplane-%02d.k8s-01", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = 40
}

resource "sakuracloud_server" "k8s-cplane" {
  count = local.k8s_cplane_count
  name  = format("cplane-%02d.k8s-01", count.index + 1)

  core   = 4
  memory = 4
  gpu    = 0

  disks = [
    element(sakuracloud_disk.k8s-cplane, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata.yaml", {
    fqdn               = format("cplane-%02d.k8s-01.%s", count.index + 1, data.sakuracloud_dns.domain_zone.zone)
    vip                = local.k8s_lb.cplane_vip
    ip_address         = cidrhost(local.k8s_cplane_cidr, count.index + 1)
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
    gateway            = local.lab_gateway_ip_address
  })
}

#
# node setup
#
resource "sakuracloud_disk" "k8s-node" {
  count             = local.k8s_node_count
  name              = format("node-%02d.k8s-01", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = 40
}

resource "sakuracloud_server" "k8s-node" {
  count = local.k8s_node_count
  name  = format("node-%02d.k8s-01", count.index + 1)

  core   = 4
  memory = 4
  gpu    = 0

  disks = [
    element(sakuracloud_disk.k8s-node, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata.yaml", {
    fqdn               = format("node-%02d.k8s-01.%s", count.index + 1, data.sakuracloud_dns.domain_zone.zone)
    vip                = ""
    ip_address         = cidrhost(local.k8s_node_cidr, count.index + 1)
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
    gateway            = local.lab_gateway_ip_address
  })
}

# lb setup
resource "sakuracloud_load_balancer" "k8s-cplane-lb" {
  name = "cplane-lb.k8s-01"
  plan = "standard"

  network_interface {
    switch_id    = data.sakuracloud_switch.k8s-lab-switch0.id
    vrid         = 1
    ip_addresses = [local.k8s_lb.ip_address]
    netmask      = 16
    gateway      = local.lab_gateway_ip_address
  }

  vip {
    vip        = cidrhost(local.k8s_cplane_cidr, 15)
    port       = 6443
    delay_loop = 10

    dynamic "server" {
      for_each = { for i, v in sakuracloud_server.k8s-cplane : i + 1 => v }
      content {
        ip_address = cidrhost(local.k8s_cplane_cidr, server.key)
        protocol   = "https"
        path       = "/livez"
        status     = 200
      }
    }
  }
}
