# 5G KPI summary

## Latency (RTT through the UE tunnel)

| platform   | run        | target   |   samples |   avg_ms |   p50_ms |   p95_ms |   p99_ms |   max_ms |   jitter_mdev_ms |   loss_pct |
|:-----------|:-----------|:---------|----------:|---------:|---------:|---------:|---------:|---------:|-----------------:|-----------:|
| freeran    | consistent | gateway  |       500 |    1.372 |     1.29 |    1.94  |    2.933 |    12.3  |            0.679 |          0 |
| freeran    | consistent | internet |       500 |   24.958 |    23.1  |   33.205 |   63.236 |   125    |            7.363 |          0 |
| oai        | consistent | gateway  |       500 |   22.125 |    21.9  |   26.505 |   31.105 |    38.9  |            2.937 |          0 |
| oai        | consistent | internet |       500 |   43.257 |    42.6  |   49.405 |   59.304 |   116    |            5.741 |          0 |
| ueransim   | consistent | gateway  |       500 |    1.697 |     1.64 |    2.271 |    3.11  |     5.82 |            0.426 |          0 |
| ueransim   | consistent | internet |       500 |   24.751 |    22.6  |   28.22  |   85.514 |   208    |           12.409 |          0 |


## Throughput (iperf3)

| platform   | run        | test         |   runs |   mean_mbps |   min_mbps |   max_mbps |   std_mbps |   udp_jitter_ms |   udp_loss_pct |
|:-----------|:-----------|:-------------|-------:|------------:|-----------:|-----------:|-----------:|----------------:|---------------:|
| freeran    | consistent | tcp_uplink   |      3 |      199.42 |     194.01 |     208.31 |       7.76 |         nan     |        nan     |
| freeran    | consistent | tcp_downlink |      3 |      306.68 |     301.25 |     313.14 |       6.01 |         nan     |        nan     |
| freeran    | consistent | udp_uplink   |      3 |       50    |      50    |      50    |       0    |           0.053 |          0     |
| oai        | consistent | tcp_uplink   |      3 |       52.22 |      51.93 |      52.5  |       0.29 |         nan     |        nan     |
| oai        | consistent | tcp_downlink |      3 |      116.04 |     114.66 |     117.18 |       1.28 |         nan     |        nan     |
| oai        | consistent | udp_uplink   |      3 |       49.98 |      49.98 |      49.98 |       0    |           0.306 |          0     |
| ueransim   | consistent | tcp_uplink   |      3 |      243.62 |     239.06 |     247.82 |       4.39 |         nan     |        nan     |
| ueransim   | consistent | tcp_downlink |      3 |      363.81 |     360.11 |     365.93 |       3.21 |         nan     |        nan     |
| ueransim   | consistent | udp_uplink   |      3 |       49.99 |      49.98 |      50    |       0.01 |           0.041 |          0.014 |


## Control plane: time from UE start to data connectivity

Cell search/sync + registration + PDU session + tunnel setup, measured the same way on every platform.

| platform   |   attempts |   success |   mean_ms |   median_ms |   min_ms |   max_ms |   p95_ms |
|:-----------|-----------:|----------:|----------:|------------:|---------:|---------:|---------:|
| freeran    |         10 |        10 |     310.3 |         308 |      298 |      326 |    324.2 |
| oai        |         10 |        10 |    1507.5 |        1476 |     1454 |     1637 |   1636.6 |
| ueransim   |         10 |        10 |     432.8 |         425 |      413 |      476 |    464.3 |


### Breakdown from UE logs (UERANSIM only; OAI logs have no timestamps)

| platform   |   registration_ms_mean |   registration_ms_median |   registration_ms_max |   pdu_session_ms_mean |   pdu_session_ms_median |   pdu_session_ms_max |
|:-----------|-----------------------:|-------------------------:|----------------------:|----------------------:|------------------------:|---------------------:|
| ueransim   |                   37.7 |                     38.5 |                    46 |                 217.4 |                     217 |                  222 |


## Multi-UE scaling

| platform   |   ues_requested |   pdu_sessions_up |   all_up_wall_s |   attach_total_ms_mean |   rtt_avg_ms |   loss_pct |   core_cpu_mean_pct |   gnb_cpu_mean_pct |   ue_cpu_mean_pct |   core_ram_peak_mb |   ue_ram_peak_mb |
|:-----------|----------------:|------------------:|----------------:|-----------------------:|-------------:|-----------:|--------------------:|-------------------:|------------------:|-------------------:|-----------------:|
| freeran    |               1 |                 1 |           0.844 |                  nan   |        1.269 |          0 |                 0.7 |                0.1 |               0   |              527   |             18.3 |
| freeran    |               2 |                 2 |           0.845 |                  nan   |        1.23  |          0 |                 0.8 |                0.1 |               0.1 |              527.3 |             18.8 |
| freeran    |               4 |                 4 |           0.962 |                  nan   |        1.265 |          0 |                 1.1 |                0.2 |               0.3 |              527.9 |             19.3 |
| freeran    |               8 |                 8 |           0.855 |                  nan   |        1.203 |          0 |                 1.4 |                0.3 |               0.4 |              528.8 |             21.9 |
| freeran    |              20 |                20 |           0.909 |                  nan   |        1.064 |          0 |                 2.4 |                0.7 |               0.8 |              531.5 |             24.2 |
| oai        |               1 |                 1 |           1.73  |                  nan   |       23.34  |          0 |                 0.6 |              164.8 |             150   |              510.4 |            362.9 |
| oai        |               2 |                 2 |           2.41  |                  nan   |       22.93  |          0 |                 0.7 |              192.3 |             261.5 |              510.8 |            725.6 |
| oai        |               4 |                 4 |           3.247 |                  nan   |       36.658 |          0 |                 0.8 |              182.9 |             309.6 |              511.4 |           1451.4 |
| oai        |               8 |                 8 |           5.867 |                  nan   |       66.769 |          0 |                 1.3 |              180.1 |             390.2 |              512.4 |           2902.6 |
| ueransim   |               1 |                 1 |           0.837 |                  268   |        1.932 |          0 |                 0.8 |                0.2 |               0.3 |              489.2 |              8.4 |
| ueransim   |               2 |                 2 |           0.955 |                  122   |        2.215 |          0 |                 0.9 |                0.3 |               0.5 |              489.7 |              8.6 |
| ueransim   |               4 |                 4 |           1.154 |                  102.5 |        1.935 |          0 |                 1   |                0.4 |               0.8 |              490.4 |              8.9 |
| ueransim   |               8 |                 8 |           1.892 |                  165   |        1.671 |          0 |                 1.6 |                0.6 |               1.6 |              491.6 |              9.9 |
| ueransim   |              20 |                20 |           4.153 |                  586.1 |        1.659 |          0 |                 2.4 |                1.1 |               3.7 |              494.5 |             12.8 |


## CPU / RAM during the single-UE tests

| platform   | component    |   cpu_mean |   cpu_peak |   ram_mean_mb |   ram_peak_mb |
|:-----------|:-------------|-----------:|-----------:|--------------:|--------------:|
| freeran    | MongoDB      |        1.8 |        5   |         392.1 |         392.1 |
| freeran    | Open5GS core |       29.2 |       95.2 |         452   |         452.8 |
| freeran    | System total |       11.5 |       32.8 |        1177.8 |        1246.6 |
| freeran    | UE(s)        |       63.2 |      179.9 |          21.1 |          24.9 |
| freeran    | gNB          |       72   |      208.4 |          24.2 |          27.8 |
| oai        | MongoDB      |        1.8 |        4   |         392.1 |         392.1 |
| oai        | Open5GS core |       10.8 |       34.5 |         508.4 |         508.9 |
| oai        | System total |       30.5 |       44.1 |        3761.6 |        3788.8 |
| oai        | UE(s)        |      204.8 |      365.7 |         367.4 |         373.8 |
| oai        | gNB          |      231.4 |      363   |        2082.1 |        2084.7 |
| ueransim   | MongoDB      |        1.6 |        4   |         392.1 |         392.1 |
| ueransim   | Open5GS core |       33.9 |      102.5 |         486.5 |         487.3 |
| ueransim   | System total |       13.4 |       42.7 |        1206.5 |        1343.2 |
| ueransim   | UE(s)        |       82.5 |      284.8 |           8.2 |           8.8 |
| ueransim   | gNB          |       73.8 |      231.5 |          11.3 |          11.7 |


## Significance tests

Pairwise, two-sided. Latency and attach time: Mann-Whitney U (no normality assumed), median difference A - B with a 95% bootstrap confidence interval, and the rank-biserial effect size r = P(A > B) - P(A < B) (between -1 and 1; 0 = no difference). Throughput (3 runs each): Welch's t-test, and the median columns hold the means. p-values are Holm-corrected across all tests in this table. Consecutive pings are not fully independent, so treat latency p-values as optimistic and judge by the effect size and interval.

| metric                  | A       | B        |   n_A |   n_B |   median_A |   median_B | difference A-B   | ci95                   | effect_r   | test            |         p |    p_holm | significant   |
|:------------------------|:--------|:---------|------:|------:|-----------:|-----------:|:-----------------|:-----------------------|:-----------|:----------------|----------:|----------:|:--------------|
| RTT to gateway          | freeran | oai      |   500 |   500 |       1.29 |      21.9  | -20.61 ms        | [-20.835, -20.360]     | -1.0       | Mann-Whitney U  | 5.88e-165 | 8.59e-164 | yes           |
| RTT to internet         | freeran | oai      |   500 |   500 |      23.1  |      42.6  | -19.5 ms         | [-19.800, -19.250]     | -0.959     | Mann-Whitney U  | 5.24e-152 | 6.81e-151 | yes           |
| Time to connectivity    | freeran | oai      |    10 |    10 |     308    |    1476    | -1168.0 ms       | [-1250.500, -1153.000] | -1.0       | Mann-Whitney U  | 0.000181  | 0.00133   | yes           |
| Throughput tcp uplink   | freeran | oai      |     3 |     3 |     199.42 |      52.22 | 147.2 Mbit/s     | [127.95, 166.45]       |            | Welch t (means) | 0.000913  | 0.00193   | yes           |
| Throughput tcp downlink | freeran | oai      |     3 |     3 |     306.68 |     116.04 | 190.64 Mbit/s    | [176.52, 204.76]       |            | Welch t (means) | 0.000191  | 0.00133   | yes           |
| RTT to gateway          | freeran | ueransim |   500 |   500 |       1.29 |       1.64 | -0.35 ms         | [-0.400, -0.295]       | -0.592     | Mann-Whitney U  | 4.79e-59  | 5.27e-58  | yes           |
| RTT to internet         | freeran | ueransim |   500 |   500 |      23.1  |      22.6  | 0.5 ms           | [0.400, 0.700]         | 0.307      | Mann-Whitney U  | 4.06e-17  | 4.06e-16  | yes           |
| Time to connectivity    | freeran | ueransim |    10 |    10 |     308    |     425    | -117.0 ms        | [-143.000, -101.500]   | -1.0       | Mann-Whitney U  | 0.00018   | 0.00133   | yes           |
| Throughput tcp uplink   | freeran | ueransim |     3 |     3 |     199.42 |     243.62 | -44.21 Mbit/s    | [-60.13, -28.28]       |            | Welch t (means) | 0.00271   | 0.00271   | yes           |
| Throughput tcp downlink | freeran | ueransim |     3 |     3 |     306.68 |     363.81 | -57.13 Mbit/s    | [-69.53, -44.73]       |            | Welch t (means) | 0.000644  | 0.00193   | yes           |
| RTT to gateway          | oai     | ueransim |   500 |   500 |      21.9  |       1.64 | 20.26 ms         | [20.030, 20.490]       | 1.0        | Mann-Whitney U  | 5.73e-165 | 8.59e-164 | yes           |
| RTT to internet         | oai     | ueransim |   500 |   500 |      42.6  |      22.6  | 20.0 ms          | [19.800, 20.300]       | 0.937      | Mann-Whitney U  | 3.62e-145 | 4.35e-144 | yes           |
| Time to connectivity    | oai     | ueransim |    10 |    10 |    1476    |     425    | 1051.0 ms        | [1024.000, 1127.000]   | 1.0        | Mann-Whitney U  | 0.00018   | 0.00133   | yes           |
| Throughput tcp uplink   | oai     | ueransim |     3 |     3 |      52.22 |     243.62 | -191.4 Mbit/s    | [-202.25, -180.55]     |            | Welch t (means) | 0.000166  | 0.00133   | yes           |
| Throughput tcp downlink | oai     | ueransim |     3 |     3 |     116.04 |     363.81 | -247.77 Mbit/s   | [-254.67, -240.86]     |            | Welch t (means) | 5.19e-06  | 4.67e-05  | yes           |


