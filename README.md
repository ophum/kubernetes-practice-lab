# kubernetes-practice-lab

k8s の勉強用

## トポロジ

![](./lab-topo.drawio.png)

### ネットワーク

| ネットワーク | CIDR           |
| ------------ | -------------- |
| wireguard    | 10.0.0.0/24    |
| lab          | 192.168.0.0/24 |

lab 内の IP アドレスはさらに以下のように分ける

| ネットワーク範囲 | 用途                            |
| ---------------- | ------------------------------- |
| 0 ~ 15           | vpc router(1), loadbalancer(15) |
| 16 ~ 31          | k8s master(16~18), lb vip(31)   |
| 32 ~ 47          | k8s worker(32~34)               |
