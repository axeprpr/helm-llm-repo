# volcano-scheduler

This directory is a chart skeleton for documenting Volcano installation
alongside the inference charts in this repo.

Current status:

- placeholder only
- no templates are shipped yet
- use upstream Volcano manifests or charts for real installation today

Related repo support:

- all inference charts support `scheduler.type=volcano`
- all inference charts can render `PodGroup` objects for gang scheduling
- real repo evidence currently covers manifest rendering, `PodGroup` creation,
  queueing, and single-pod failure reproduction on `ENV-42`

Recommended next step:

- add packaged Volcano install manifests or upstream chart wiring once the repo
  is ready to manage scheduler lifecycle directly
