locals {
  lab_wireguard_cidr = "10.0.0.0/24"
  lab_cidr           = cidrsubnet("192.168.0.0/24", 4, 0)
  k8s_master_cidr    = cidrsubnet("192.168.0.0/24", 4, 1)
  k8s_worker_cidr    = cidrsubnet("192.168.0.0/24", 4, 2)
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
  os_type = "ubuntu"
}

# dns
data "sakuracloud_dns" "domain_zone" {
  filter {
    names = [var.domain_zone]
  }
}

resource "sakuracloud_dns_record" "k8s-master-lb" {
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = "k8s-master"
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.k8s_master_cidr, 15)
}

resource "sakuracloud_dns_record" "k8s-master" {
  count  = 3
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("k8s-master-%02d", count.index)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.k8s_master_cidr, count.index)
}

resource "sakuracloud_dns_record" "k8s-worker" {
  count  = 3
  dns_id = data.sakuracloud_dns.domain_zone.id
  name   = format("k8s-worker-%02d", count.index)
  type   = "A"
  ttl    = 60
  value  = cidrhost(local.k8s_worker_cidr, count.index)
}

#
# master setup
#
resource "sakuracloud_disk" "k8s-master" {
  count             = 3
  name              = format("k8s-master-%02d", count.index)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = 40
}

resource "sakuracloud_server" "k8s-master" {
  count = 3
  name  = format("k8s-master-%02d", count.index)

  core   = 4
  memory = 4
  gpu    = 0

  disks = [
    element(sakuracloud_disk.k8s-master, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  disk_edit_parameter {
    hostname    = format("k8-master-%02d", count.index)
    ip_address  = cidrhost(local.k8s_master_cidr, count.index)
    netmask     = 24
    gateway     = "192.168.0.1"
    ssh_key_ids = [data.sakuracloud_ssh_key.initial.id]
  }
}

#
# worker setup
#
resource "sakuracloud_disk" "k8s-worker" {
  count             = 3
  name              = format("k8s-worker-%02d", count.index)
  source_archive_id = data.sakuracloud_archive.ubuntu.id
  size              = 40
}

resource "sakuracloud_server" "k8s-worker" {
  count = 3
  name  = format("k8s-worker-%02d", count.index)

  core   = 4
  memory = 4
  gpu    = 0

  disks = [
    element(sakuracloud_disk.k8s-worker, count.index).id
  ]

  network_interface {
    upstream = data.sakuracloud_switch.k8s-lab-switch0.id
  }

  disk_edit_parameter {
    hostname    = format("k8-worker-%02d", count.index)
    ip_address  = cidrhost(local.k8s_worker_cidr, count.index)
    netmask     = 24
    gateway     = "192.168.0.1"
    ssh_key_ids = [data.sakuracloud_ssh_key.initial.id]
  }
}

# lb setup
resource "sakuracloud_load_balancer" "k8s-master-lb" {
  name = "k8s-master-lb"
  plan = "standard"

  network_interface {
    switch_id    = data.sakuracloud_switch.k8s-lab-switch0.id
    vrid         = 1
    ip_addresses = [cidrhost(local.lab_cidr, 15)]
    netmask      = 24
    gateway      = "192.168.0.1"
  }

  vip {
    vip        = cidrhost(local.k8s_master_cidr, 15)
    port       = 6443
    delay_loop = 10

    dynamic "server" {
      for_each = { for i in [0, 1, 2] : i => i }
      content {
        ip_address = cidrhost(local.k8s_master_cidr, server.key)
        protocol   = "https"
        path       = "/livez"
        status     = 200
      }
    }
  }
}
