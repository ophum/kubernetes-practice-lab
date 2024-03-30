locals {
  lab_wireguard_cidr     = "10.0.0.0/24"
  lab_cidr               = "172.31.0.0/16"
  lab_common_cidr        = "172.31.0.0/24"
  lab_gateway_ip_address = "172.31.0.1"
}

locals {
  k8s_cidr = cidrsubnet(local.lab_cidr, 8, 2)
}

locals {
  cplane = {
    cidr      = cidrsubnet(local.k8s_cidr, 4, 0)
    count     = 1
    vcpus     = 4
    memory    = 4
    disk_size = 40
  }
  node = {
    cidr      = cidrsubnet(local.k8s_cidr, 4, 1)
    count     = 3
    vcpus     = 4
    memory    = 4
    disk_size = 40
  }
  lb_cidr = cidrsubnet(local.k8s_cidr, 4, 2)
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


resource "sakuracloud_disk" "cplane" {
  count             = local.cplane.count
  name              = format("cplane-%02d.k8s-02", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = local.cplane.disk_size
}

resource "sakuracloud_server" "cplane" {
  count = local.cplane.count
  name  = format("cplane-%02d.k8s-02", count.index + 1)

  core   = local.cplane.vcpus
  memory = local.cplane.memory
  gpu    = 0

  disks = [
    element(sakuracloud_disk.cplane, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata.yaml", {
    fqdn               = format("cplane-%02d.k8s-02.%s", count.index + 1, data.sakuracloud_dns.domain_zone.zone)
    vip                = ""
    ip_address         = cidrhost(local.cplane.cidr, count.index + 1)
    gateway            = local.lab_gateway_ip_address
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
  })
}

resource "sakuracloud_dns_record" "cplane" {
  count  = local.cplane.count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("cplane-%02d.k8s-02", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.cplane.cidr, count.index + 1)
}

resource "sakuracloud_disk" "node" {
  count             = local.node.count
  name              = format("node-%02d.k8s-02", count.index + 1)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = local.node.disk_size
}

resource "sakuracloud_server" "node" {
  count = local.node.count
  name  = format("node-%02d.k8s-02", count.index + 1)

  core   = local.node.vcpus
  memory = local.node.memory
  gpu    = 0

  disks = [
    element(sakuracloud_disk.node, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  user_data = templatefile("userdata.yaml", {
    fqdn               = format("node-%02d.k8s-02.%s", count.index + 1, data.sakuracloud_dns.domain_zone.zone)
    vip                = local.lb.ingress_vip
    ip_address         = cidrhost(local.node.cidr, count.index + 1)
    gateway            = local.lab_gateway_ip_address
    ssh_authorized_key = data.sakuracloud_ssh_key.initial.public_key
  })
}

resource "sakuracloud_dns_record" "node" {
  count  = local.node.count
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("node-%02d.k8s-02", count.index + 1)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.node.cidr, count.index + 1)
}

resource "sakuracloud_load_balancer" "lb" {
  name = "lb.k8s-02"
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
      for_each = { for i, v in sakuracloud_server.node : i + 1 => v }
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
      for_each = { for i, v in sakuracloud_server.node : i + 1 => v }
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
  name   = "app.k8s-02"
  type   = "A"
  ttl    = 60
  value  = local.lb.ingress_vip
}
