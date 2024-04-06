# vagrant で構築

control-plane 1 台 worker2 台の構成です。
worker には 30GB のディスクを追加します。

## kubespray

```
ansible-playbook -i hosts -b -u vagrant ../kubespray/cluster.yml
```
