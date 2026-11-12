# OAI 5G NR PHY Evaluation under AWGN Channel Conditions

## 1. Overview

This directory contains a follow-on physical-layer evaluation of OpenAirInterface (OAI) using its RF simulator and AWGN channel model.

The objective is to investigate how configured downlink noise power affects UE-observed SS-SINR and SS-RSRP, along with gNB-observed PUCCH/PUSCH SNR and transport-block BLER.

This is a separate PHY-focused experiment and its results must not be mixed with the original UERANSIM, free-ran-ue and OAI benchmark measurements.

## 2. Experimental Environment

- Platform: Ubuntu 22.04.5 under WSL2
- Radio stack: OpenAirInterface 5G
- OAI revision: 2026.w42
- Core network: Open5GS
- Radio simulation: OAI RF simulator
- Channel model: AWGN
- NR band: n78
- Carrier frequency: 3.6048 GHz
- Bandwidth: 24 resource blocks
- Numerology: 1
- PLMN: 001/01
- TAC: 1
- S-NSSAI: SST 1
- DNN: internet
- Configured path loss: -10 dB
- Capture duration: approximately 60 seconds per condition

No physical SDR or over-the-air radio link was used.
## 3. AWGN Sweep Methodology

The downlink noise power was varied while uplink noise power and configured path loss were kept constant.

| Parameter | Value |
|---|---|
| DL noise power | -19, -15, -10, -8, -7 dB |
| UL noise power | -17 dB |
| DL path loss | -10 dB |
| UL path loss | -10 dB |
| Capture duration | Approximately 60 seconds |

The OAI channel model was explicitly enabled using:

`--rfsimulator.[0].options chanmod`

The original OAI benchmark did not use this option. It was an RF-simulator run without channel modelling, not an AWGN experiment.

## 4. Measured Metrics

### UE-side metrics

- SS-SINR: Synchronization Signal Signal-to-Interference-plus-Noise Ratio
- SS-RSRP: Synchronization Signal Reference Signal Received Power
- RI: Rank Indicator
- CQI: Channel Quality Indicator

CQI was reported as N/A in the collected runtime output and is not treated as a numerical measurement.

### gNB-side metrics

- Average RSRP
- PUCCH SNR
- PUSCH SNR
- Downlink BLER
- Uplink BLER
- HARQ decoding errors
- Uplink MCS and NPRB
## 5. UE Measurement Results

| DL noise (dB) | Samples | Mean SS-SINR (dB) | Std. dev. (dB) | Mean SS-RSRP (dBm) |
|---:|---:|---:|---:|---:|
| -19 | 136 | 28.13 | 0.68 | -46.00 |
| -15 | 67 | 20.19 | 0.62 | -45.85 |
| -10 | 78 | 10.13 | 0.59 | -45.00 |
| -8 | 104 | 6.10 | 0.85 | -44.75 |
| -7 | 184 | 4.12 | 0.95 | -44.09 |

The measured mean SS-SINR decreased monotonically as configured downlink noise increased. The total decrease between the -19 dB and -7 dB conditions was approximately 24.01 dB.

SS-RSRP remained within a relatively narrow range.

## 6. gNB Measurement Results

| DL noise (dB) | Samples | Mean gNB RSRP (dBm) | PUCCH SNR (dB) | PUSCH SNR (dB) |
|---:|---:|---:|---:|---:|
| -19 | 136 | -44.99 | 22.02 | 16.64 |
| -15 | 67 | -44.00 | 22.05 | 16.73 |
| -10 | 78 | -44.00 | 22.01 | 16.75 |
| -8 | 104 | -43.00 | 22.05 | 16.70 |
| -7 | 169 | -43.00 | 22.00 | 16.64 |

The uplink noise configuration was held constant. PUCCH and PUSCH SNR therefore remained relatively stable across the downlink sweep.
## 7. BLER Observations

| DL noise (dB) | Mean DL BLER | Mean UL BLER |
|---:|---:|---:|
| -19 | 0 | 0 |
| -15 | 0 | 0 |
| -10 | 0 | 0 |
| -8 | 0 | 0 |
| -7 | 0 | 2.96 x 10^-7 |

At -7 dB, the maximum observed UL BLER sample was approximately 4.0 x 10^-5.

The low BLER values should be interpreted in the context of the conservative MCS and low code-rate operation observed during these runs. They do not establish a general radio-link reliability limit.

## 8. Initial-Access Failure at -6 dB

A separate experiment was conducted with DL noise power configured to -6 dB.

Observed behaviour:

1. Cell search and synchronization were successful.
2. PBCH decoding was successful.
3. The UE repeatedly received SIB1 decoding failures.
4. Repeated BCCH-DL-SCH NACK messages were observed.
5. Successful random access and connected-mode operation were not confirmed in this run.

This is an initial-access broadcast decoding failure observation. It is not a connected-mode BLER measurement.

Only one run is documented here; further repetitions are required before making a statistical claim about a failure threshold.
## 9. Reproducing the Analysis

Run the following commands from the repository root.

### Requirements

Install the Python dependencies:

    python3 -m pip install -r requirements.txt

### Extract UE and gNB measurements

    python3 results/oai_phy_awgn/analysis/extract_ue_dl7.py
    python3 results/oai_phy_awgn/analysis/extract_gnb_dl7.py

These scripts extract the -7 dB UE and gNB measurements from the corresponding raw logs.

### Generate AWGN comparison datasets and plots

    python3 results/oai_phy_awgn/analysis/compare_awgn.py

The script reads the CSV datasets in this folder and generates:

- Consolidated UE and gNB CSV datasets
- AWGN comparison summary CSV
- Six comparison plots

All paths are resolved relative to the repository, so the analysis does not depend on the original experiment directory.

Note: The extraction scripts reproduce the -7 dB datasets. The consolidated AWGN comparison uses the CSV datasets already included in this repository.
