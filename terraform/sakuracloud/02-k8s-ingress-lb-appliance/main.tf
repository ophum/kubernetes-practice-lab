locals {
  lab_wireguard_cidr = "10.0.0.0/24"
  lab_cidr           = cidrsubnet("192.168.0.0/24", 4, 0)
  control_plane = {
    cidr      = cidrsubnet("192.168.0.0/24", 4, 3)
    count     = 1
    vcpus     = 4
    memory    = 4
    disk_size = 40
  }
  node = {
    cidr      = cidrsubnet("192.168.0.0/24", 4, 4)
    count     = 3
    vcpus     = 4
    memory    = 4
    disk_size = 40
  }
  lb_cidr = cidrsubnet("192.168.0.0/24", 4, 5)
}

locals {
  lb = {
    ip_address  = cidrhost(local.lb_cidr, 1)
    ingress_vip = cidrhost(local.lb_cidr, 2)
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

data "sakuracloud_dns" "domain_zone" {
  filter {
    names = [var.domain_zone]
  }
}


# archive
data "sakuracloud_archive" "ubuntu" {
  filter {
    id = 113501244081
  }
}


resource "sakuracloud_disk" "control_plane" {
  count             = local.control_plane.count
  name              = format("control-plane-%02d.test02", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = local.control_plane.disk_size
}

resource "sakuracloud_server" "control_plane" {
  count = local.control_plane.count
  name  = format("control-plane-%02d.test02", count.index + 1)

  core   = local.control_plane.vcpus
  memory = local.control_plane.memory
  gpu    = 0

  disks = [
    element(sakuracloud_disk.control_plane, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata.yaml", {
    fqdn               = format("control-plane-%02d.test02", count.index + 1)
    ip_address         = cidrhost(local.control_plane.cidr, count.index + 1)
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
  })
}

resource "sakuracloud_dns_record" "control_plane" {
  count  = local.control_plane.count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("control-plane-%02d.test02", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.control_plane.cidr, count.index + 1)
}

resource "sakuracloud_disk" "node" {
  count             = local.node.count
  name              = format("node-%02d.test02", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = local.node.disk_size
}

resource "sakuracloud_server" "node" {
  count = local.node.count
  name  = format("node-%02d.test02", count.index + 1)

  core   = local.node.vcpus
  memory = local.node.memory
  gpu    = 0

  disks = [
    element(sakuracloud_disk.node, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata-node.yaml", {
    fqdn               = format("node-%02d.test02", count.index + 1)
    ip_address         = cidrhost(local.node.cidr, count.index + 1)
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
  })
}

resource "sakuracloud_dns_record" "node" {
  count  = local.node.count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("node-%02d.test02", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.node.cidr, count.index + 1)
}

resource "sakuracloud_load_balancer" "lb" {
  name = "lb.test02"
  plan = "standard"

  network_interface {
    switch_id    = data.sakuracloud_switch.k8s-lab-switch0.id
    vrid         = 2
    ip_addresses = [local.lb.ip_address]
    netmask      = 24
    gateway      = "192.168.0.1"
  }

  vip {
    vip        = local.lb.ingress_vip
    port       = 80
    delay_loop = 10

    dynamic "server" {
      for_each = { for i in [1, 2, 3] : i => i }
      content {
        ip_address = cidrhost(local.node.cidr, server.key)
        protocol   = "http"
        path       = "/"
        status     = 404
      }
    }
  }

  vip {
    vip        = local.lb.ingress_vip
    port       = 443
    delay_loop = 10

    dynamic "server" {
      for_each = { for i in [1, 2, 3] : i => i }
      content {
        ip_address = cidrhost(local.node.cidr, server.key)
        protocol   = "https"
        path       = "/"
        status     = 404
      }
    }
  }
}

resource "sakuracloud_dns_record" "app" {
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = "app.test02"
  type   = "A"
  ttl    = 60
  value  = local.lb.ingress_vip
}
