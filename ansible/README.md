```
ansible-playbook -i hosts --become -u ubuntu -e "@./all.yml" -e "@./addons.yml" -e "@./k8s-cluster.yml" kubespray/cluster.yml
```
