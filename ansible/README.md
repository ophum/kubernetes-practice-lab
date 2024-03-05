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

## argocd セットアップ

argocd をセットアップします。
ローカルから k8s-master に接続できる必要があります。(FIXME: できれば k8s-master-00 上で完結させたい)

```
ansible-playbook -i hosts -e "@./argocd_encrypted.yml" setup-argocd.yml --ask-vault-pass
```
