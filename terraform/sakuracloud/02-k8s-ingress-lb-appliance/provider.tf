terraform {
  required_providers {
    sakuracloud = {
      source  = "sacloud/sakuracloud"
      version = "2.25.0"
    }
  }
}

variable "sakuracloud_profile" {
  type    = string
  default = "default"
}
provider "sakuracloud" {
  profile = var.sakuracloud_profile
  zone    = "tk1b"
}
