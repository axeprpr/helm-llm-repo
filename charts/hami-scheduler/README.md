# hami-scheduler

This directory is a chart skeleton for documenting HAMi installation alongside
the inference charts in this repo.

Current status:

- placeholder only
- no templates are shipped yet
- use the upstream HAMi release chart for real installation today

Related repo support:

- all inference charts support `scheduler.type=hami`
- `vllm-inference` also renders HAMi node/GPU policy annotations and
  `nvidia.com/gpumem-percentage`
- real repo evidence currently covers single-pod HAMi scheduling and UUID-bound
  allocation on `ENV-42`
- true multi-pod shared-GPU validation is still pending

Recommended next step:

- add packaged HAMi install manifests or upstream chart wiring once the repo is
  ready to manage scheduler lifecycle directly
