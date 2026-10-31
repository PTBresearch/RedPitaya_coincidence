# Red Pitaya Coincidence Counter

FPGA-basierter Koinzidenzzähler für ein Red Pitaya (STEMlab 125-14), entwickelt an der Physikalisch-Technischen Bundesanstalt (PTB). Der Zähler detektiert gleichzeitige Ereignisse an zwei Detektoreingängen und stellt die Zählerstände über einen TCP-Server bereit.

![Breakout-Board](doc/images/rp_breakout_platine.png)

## Funktionsbeschreibung

Der Counter hat zwei Detektor-Eingänge und 6 Monitor-Ausgänge. Sind beide Detektor-Eingänge innerhalb eines Zeitfensters von 5 ns gleichzeitig high, wird dies als „Coincidence Event" gezählt.

Die Abtastrate für die beiden Eingänge beträgt 200 MHz.

### Elektrische Eigenschaften

| | |
|---|---|
| **Eingänge** | Logic-Level 0–1,8 V, Impedanz 1 MΩ |
| **Ausgänge** | Logic-Level 0–1,8 V, 2 mA |

### Pin-Beschreibung

| Pin | Funktion |
|---|---|
| 1 | Eingang Detektor 1 |
| 2 | Eingang Detektor 2 |
| 3 | Ausgang Monitor, Event Detektor 1 (toggle) |
| 4 | Ausgang Monitor, Event Detektor 2 (toggle) |
| 5 | Ausgang Monitor, Event Coincidence (toggle) |
| 6 | Ausgang Monitor, Event Detektor 1 (pulse) |
| 7 | Ausgang Monitor, Event Detektor 2 (pulse) |
| 8 | Ausgang Monitor, Event Coincidence (pulse) |

Eingangsbeschaltung: BNC → 300 Ω → FPGA → 300 Ω → GND

## Zähler und Betriebsarten

Der Zähler kann per Befehl zurückgesetzt werden; dabei werden alle Zählerstände auf null gesetzt. Für jeden Eingang und für den Coincidence-Fall existieren individuelle Zähler, die einzeln oder im Block gelesen werden können. Es werden folgende Betriebsarten unterschieden:

1. **on the fly** – Die Zählerstände wachsen kontinuierlich an.
2. **100 ms / 1 s / 2 s / 5 s / 10 s** – Die Zählerstände enthalten jeweils aggregierte Werte über das genannte Zeitintervall.

Für die Betriebsarten 2–6 existiert jeweils ein Index, um die Werte zeitlich zuordnen zu können.

## Kommunikation

Die Kommunikation erfolgt über **TCP-Port 1001**. Auf dem Red Pitaya läuft ein Server, der folgende Kommandos entgegennimmt. Der Server erwartet immer ein Feld mit 3 Integer-Werten (12 Bytes):

| Feld | Bedeutung |
|---|---|
| Integer 1 | command |
| Integer 2 | address |
| Integer 3 | value |

### Kommandos

| Kommando | Bedeutung | Antwort |
|---|---|---|
| `1` (reset) | Alle Zähler werden zurückgesetzt | 0 Integer (nichts) |
| `2` (read value) | Ein Zähler wird gelesen, mit Index | 2 Integer `[Zählerstand, Index]` (8 Bytes) |
| `10` (read all) | Alle Zähler werden gelesen, mit Index | 23 Integer (92 Bytes) |

### Registerübersicht (Antwort auf `read all`)

| Beschreibung | Address | Index |
|---|---|---|
| cnt_detector_1_fly | 0x00100 | 0 |
| cnt_detector_1_100ms | 0x00104 | 1 |
| cnt_detector_1_1s | 0x00108 | 2 |
| cnt_detector_1_2s | 0x0010C | 3 |
| cnt_detector_1_5s | 0x00110 | 4 |
| cnt_detector_1_10s | 0x00114 | 5 |
| cnt_detector_2_fly | 0x00200 | 6 |
| cnt_detector_2_100ms | 0x00204 | 7 |
| cnt_detector_2_1s | 0x00208 | 8 |
| cnt_detector_2_2s | 0x0020C | 9 |
| cnt_detector_2_5s | 0x00210 | 10 |
| cnt_detector_2_10s | 0x00214 | 11 |
| cnt_channel_1_fly | 0x00300 | 12 |
| cnt_channel_1_100ms | 0x00304 | 13 |
| cnt_channel_1_1s | 0x00308 | 14 |
| cnt_channel_1_2s | 0x0030C | 15 |
| cnt_channel_1_5s | 0x00310 | 16 |
| cnt_channel_1_10s | 0x00314 | 17 |
| index_100ms | 0x00400 | 18 |
| index_1s | 0x00404 | 19 |
| index_2s | 0x00408 | 20 |
| index_5s | 0x0040C | 21 |
| index_10s | 0x00410 | 22 |

## Repository-Struktur

```text
FPGA_Project_Classic/   Vivado-Projekt (RTL, Simulation, IP-Kern-Repos, Board-Design)
src/driver/             TCP-Server für die Kommunikation (Red Pitaya / Linux)
FPGA Doc/               Dokumentation, Schaltungsbeschreibung, Bilder
```

## Voraussetzungen

- Red Pitaya STEMlab 125-14 (Xilinx Zynq-7010, `xc7z010clg400-1`)
- Xilinx Vivado **2020.2** (das mitgelieferte Block-Design-Skript `system.tcl` wurde mit Vivado 2017.2 generiert – bitte vor dem Build die IP-Status-Prüfung in Vivado ausführen)
- Red Pitaya OS mit Netzwerkzugriff auf das Board

## Build

1. Vivado öffnen und das Projekt unter `FPGA_Project_Classic/project` öffnen (oder das Projekt aus den mitgelieferten Quelldateien neu erzeugen).
2. Bitstream generieren und auf das Red Pitaya laden (z. B. per `scp` nach `/root` und U-Boot-/FPGA-Loader, siehe Red-Pitaya-Dokumentation).
3. Den TCP-Server aus `src/driver` auf dem Red Pitaya starten.

## Lizenz

Copyright 2024 Physikalisch-Technische Bundesanstalt (PTB), German National Metrology Institute.

Dieses Projekt steht unter der **Apache License 2.0** – siehe Datei [LICENSE](LICENSE).

Hinweise zu Drittanbieter-Anteilen (Xilinx-/Vivado-generierte Dateien, Red-Pitaya-Dateien), die unter ihren eigenen Lizenzbedingungen stehen, finden sich in der Datei [NOTICE](NOTICE).