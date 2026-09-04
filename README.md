# rsc-empty-sla-cleanup
A PowerShell script that safely deletes Rubrik Security Cloud (RSC) SLA Domains whose name contains a given substring — but only when the SLA Domain currently has zero objects (workloads) assigned to it. Anything still in use is listed as skipped and is never touched.
