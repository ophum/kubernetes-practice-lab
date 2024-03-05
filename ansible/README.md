# ansible

## master ノード初期セットアップ

master ノードを LB アプライアンスで冗長化するにあたって DSR 用の VIP を loopback インターフェースに設定します。

```
ansible-playbook -i hosts setup-k8s-master-lo.yml
```

## kubernetes セットアップ

kubespray でセットアップします。

```
ansible-playbook -i hosts --become -u ubuntu -e "@./extra_vars.yml" kubespray/cluster.yml
```
