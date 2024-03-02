variable "wireguard_peers" {
  type = list(object({
    name       = string
    public_key = string
  }))
}
