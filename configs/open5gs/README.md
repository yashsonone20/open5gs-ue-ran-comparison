# Open5GS 2.8.0 configuration

Stock configuration from `ppa:open5gs/latest`, with one change for all final runs:
`network_name` is commented out in `/etc/open5gs/amf.yaml` (free-ran-ue cannot decode the
UCS-2 network name). `patches/free-ran-ue-open5gs.sh` makes this change and keeps a backup
in `amf.yaml.bak`.

Defaults the other configs rely on: PLMN 999/70, TAC 1, AMF NGAP 127.0.0.5:38412,
UPF GTP-U 127.0.0.7:2152, UE pool 10.45.0.0/16 on `ogstun` (10.45.0.1), slice SST 1 (no SD).

Subscribers (all with K 465B5CE8B199B49FAA5F0A2EE238A6BC and OPc E8ED289DEBA952E4283B54E88E6183CA,
the public test values from UERANSIM's example config):
- UERANSIM: 999700000000001 to ...020
- OAI: 999700000000100 to ...107
- free-ran-ue: 999700000000110 to ...129

`scripts/02_add_subscribers.sh` adds them (`PLATFORM=oai` / `PLATFORM=freeran` for the others).
