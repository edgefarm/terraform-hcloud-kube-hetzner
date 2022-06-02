# Doc: https://rancher.com/docs/rke2/latest/en/upgrades/automated/
# agent plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: rke2-agent
  namespace: system-upgrade
  labels:
    rke2_upgrade: agent
spec:
  concurrency: 1
  channel: https://update.rke2.io/v1-release/channels/${channel}
  serviceAccountName: system-upgrade
  nodeSelector:
    matchExpressions:
      - {key: rke2_upgrade, operator: Exists}
      - {key: rke2_upgrade, operator: NotIn, values: ["disabled", "false"]}
      - {key: node-role.kubernetes.io/master, operator: NotIn, values: ["true"]}
  tolerations:
    - {key: server-usage, effect: NoSchedule, operator: Equal, value: storage}
  prepare:
    image: rancher/rke2-upgrade
    args: ["prepare", "rke2-server"]
  drain:
    force: true
    skipWaitForDeleteTimeout: 60
  upgrade:
    image: rancher/rke2-upgrade
---
# server plan
apiVersion: upgrade.cattle.io/v1
kind: Plan
metadata:
  name: rke2-server
  namespace: system-upgrade
  labels:
    rke2_upgrade: server
spec:
  concurrency: 1
  channel: https://update.rke2.io/v1-release/channels/${channel}
  serviceAccountName: system-upgrade
  nodeSelector:
    matchExpressions:
      - {key: rke2_upgrade, operator: Exists}
      - {key: rke2_upgrade, operator: NotIn, values: ["disabled", "false"]}
      - {key: node-role.kubernetes.io/master, operator: In, values: ["true"]}
  tolerations:
    - {key: node-role.kubernetes.io/master, effect: NoSchedule, operator: Exists}
    - {key: CriticalAddonsOnly, effect: NoExecute, operator: Exists}
  cordon: true
  upgrade:
    image: rancher/rke2-upgrade
