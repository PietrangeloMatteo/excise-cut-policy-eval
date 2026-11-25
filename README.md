# Who benefited from the 2022 Italian fuel excise cut?

Station-level evidence on the pass-through of the Italian excise cut of 22 March 2022, using France as a control group.

On 22 March 2022 Italy cut excise duties on petrol and diesel by 25 euro cents per litre (30.5 cents including VAT). This project measures how much of the cut reached consumers at the pump, using daily prices for almost every road fuel station in Italy and France, a difference-in-differences design, and a sensitivity analysis for violations of parallel trends.

## Main findings

- **Fast and large pass-through.** The Italy–France price gap falls by about 30 cents between 21 and 24 March and stays at the new level. On 23 March, 72% of Italian stations change their price.
- **Main estimate: petrol pass-through of 0.84–0.87 within two days.** In March 2022 Italian and French prices did not move in parallel: Italian prices followed the post-invasion price spike with a lag, and the gap was already closing in the days before the cut. Extrapolating the pre-cut trend gives 0.84–0.87; other counterfactuals built from the days around the cut give up to 1.06.
- **Robust lower bound.** Even when post-cut deviations from parallel trends are allowed to be 50% larger than the largest pre-cut deviation (Rambachan and Roth, 2023), at least 58% of the cut on petrol was passed through within two days.
- **No real difference between fuels.** Estimates are higher for diesel, but Italian prices fell by almost the same amount for both fuels (−28.6 and −29.1 cents between 21 and 24 March). The difference comes from French diesel prices, which rose by 6.4 cents in those days. The rise matches a global diesel shock (New York wholesale prices) and is similar in Mediterranean and northern France, but Italian stations would plausibly have passed it on with a lag, so diesel estimates are upper bounds.
- **Cost controls do not explain the divergence.** Lagged Brent and New York Harbor product prices fail an out-of-sample test on the March pre-period.
- **Replication on a second event.** The French fuel rebate of 1 April 2022, with Italy as control, gives a pass-through of 0.79 for petrol.

## Repository structure

```
ROOT/
├── code/                  Stata do-files (run everything from 00_master.do)
├── data/                  not included: raw/ (original data, see "Data"),
│                          temp/ and processed/ (created by the code)
├── output/
│   ├── figures_en/        figures used in the paper and slides (English labels)
│   └── tables/            estimates (.csv) and LaTeX tables (.tex)
├── paper/                 LaTeX source of the paper (main.tex) and bibliography
└── presentation/          Beamer slides (slides.tex) and compiled PDF
```

Created by the code but not included in the repository: `output/figures/` (working figures with Italian labels), the `.dta` versions of the tables, `logs/` and `sim/` (simulated data and results from `98_simulation_test.do`).

## Data

Raw data are not distributed with the code. Download them from the original sources and place them in `data/raw/` with the names below.

| Source | What | Expected location in `data/raw/` |
|---|---|---|
| MIMIT, *Carburanti – archivio prezzi* (open data of the Italian Ministry of Enterprises and Made in Italy) | Daily 8:00 snapshots of prices and station registry, Q1–Q2 2022 | `2022_1_tr_price/prezzo_alle_8-AAAAMMGG.csv`, `2022_2_tr_price/...`, `2022_1_tr-an/anagrafica_impianti_attivi-AAAAMMGG.csv`, `2022_2_tr-an/...` |
| prix-carburants.gouv.fr (French government open data) | Annual archive 2022: every price change at every station, with time stamp | `PrixCarburants_annuel_2022.xml` (the file, or a folder containing it) |
| FRED (Federal Reserve Bank of St. Louis) | Brent (`DCOILBRENTEU`), USD per EUR (`DEXUSEU`), NY Harbor conventional gasoline (`DGASNYH`) and ULSD (`DDFUELNYH`), daily | `DCOILBRENTEU.csv`, `DEXUSEU.csv`, `DGASNYH.csv`, `DDFUELNYH.csv` (from 1 November 2021 to 30 June 2022 at least) |

Brent and the exchange rate are required for the cost-control specifications; the two New York Harbor series are optional. Check the license of each source before redistributing any derived data.

**Known data issues**, all handled by the code:

- The MIMIT archive has no files for **15 and 16 March 2022**. The balanced panel is defined over the days for which each country has data.
- About 0.3% of rows in the MIMIT registry have extra fields because addresses contain the HTML entity `&#039;`. The reader re-aligns the last four columns (municipality, province, coordinates) from the right.
- Missing values in the MIMIT registry are coded as `NULL`.
- The MIMIT registry still uses the **pre-2016 Sardinian province codes** for part of the stations, so Italy has 111 province codes instead of 107.
- French prices are recorded only when they change. The code reconstructs the price in force at **8:00** each day, to match the Italian snapshots.

## Requirements

- **Stata 16 or later**, with **Python integration** configured (used only to parse the French XML file; see `help python`).
- Stata packages, installed automatically from SSC on first run: `ftools`, `reghdfe`, `coefplot`, `honestdid`. `honestdid` needs its compiled plugin: `honestdid _plugin_check` should report that the plugins are loaded.
- A LaTeX distribution to compile the paper (pdflatex + BibTeX).

## How to run

1. Open `code/00_master.do` and set the project root:
   ```stata
   global ROOT "/path/to/project"
   ```
2. Choose which steps to run with the switches in section 4 of the master (`1` = run, `0` = skip). On a first run, set all of them to `1` and `FR_REPARSE = 1`.
3. Run the master. It creates all output folders, runs the selected scripts in order and writes a log to `logs/00_master.log`.
4. Compile the paper from `paper/`: `pdflatex main`, `bibtex main`, `pdflatex main`, `pdflatex main`.

The French XML file is parsed once into `data/temp/fr_changes.csv`. Later runs reuse that file unless `FR_REPARSE = 1`, so changing the French petrol product (`FR_PETROL`) does not require parsing the XML again.

### Main parameters (set in `00_master.do`)

| Global | Default | Meaning |
|---|---|---|
| `T0_IT`, `T0_FR` | 22 Mar 2022, 1 Apr 2022 | Entry into force of the Italian cut and of the French rebate |
| `CUT_IT`, `CUT_FR` | 30.5, 18 | Size of the two cuts, cents per litre including VAT |
| `PANEL_START`, `PANEL_END` | 1 Jan – 30 Jun 2022 | Period of the processed panel |
| `WIN_START`, `WIN_END` | 1 – 26 Mar 2022 | Window on which the balanced panel is defined |
| `EST_END` | 31 Mar 2022 | End of the estimation window for the Italian cut |
| `IT_SELF` | 1 | Keep only self-service prices in Italy |
| `FR_PETROL` | `SP95` | French petrol product used as comparison (`SP95` = E5, as in Italy; alternative `E10`) |
| `STALE_MAX` | 30 | Prices not updated for more than this many days are flagged as stale |
| `PMIN`, `PMAX` | 1, 3 | Prices outside this range (euro per litre) are treated as errors |

## Pipeline

| Script | What it does | Main outputs |
|---|---|---|
| `00_master.do` | Paths, parameters, folders, switches; runs the other scripts | `logs/00_master.log` |
| `01_clean_italy.do` | Reads the daily MIMIT price and registry files, keeps standard petrol and diesel, merges station characteristics, excludes duty-free areas | `data/temp/italy_clean.dta` |
| `02_clean_france.do` | Parses the French XML (Python), reconstructs daily 8:00 prices, excludes Corsica and overseas departments | `data/temp/france_clean.dta` |
| `03_build_panel.do` | Appends the two countries, cleans prices, builds treatment variables and sample flags | `data/processed/panel_carburanti_2022.dta` |
| `04_visualization.do` | Descriptive figures (Italian labels) | `output/figures/*.png` |
| `05_clean_costs.do` | Brent, exchange rate and product prices in euro cents per litre, with lag blocks | `data/processed/costi_daily.dta` |
| `06_estimation.do` | Specifications S1–S7 (see below) | `output/tables/risultati_passthrough.*`, `event_study_coef.dta` |
| `07_honestdid.do` | Event study with 21 March as reference; Rambachan–Roth sensitivity analysis | `output/tables/event_study_rif21.dta`, `output/figures/hd_*.png` |
| `08_paper_outputs.do` | All paper figures with English labels; descriptive and results tables in LaTeX | `output/figures_en/*.png`, `output/tables/tab_*.tex` |
| `09_announcement.do` | Event study with 18 March (last price before the announcement) as reference; cluster check | `output/tables/event_study_ref18.dta`, `passthrough_ref18.*`, `tab_es_ref18.tex`, `cluster_check.csv` |
| `10_diesel_check.do` | Is the French diesel rise after the cut a common shock? Comparison with New York wholesale prices; pass-through with Mediterranean vs. rest of France as control | `output/tables/diesel_check_*.csv`, `tab_diesel_check.tex`, `fig_diesel_check_*.png` |
| `11_placebo.do` | Placebo-in-time inference: the same three-day Italy–France gap change at every date without tax changes (Jan–Jun 2022) | `output/tables/placebo_*.csv`, `tab_placebo.tex`, `fig_placebo_*.png` |
| `98_simulation_test.do` | Runs 06, 07 and 09 on simulated data with known pass-through and checks that they recover it | `sim/`, PASS/FAIL report in the log |
| `99_tests.do` | Automated checks on data, estimates and outputs | PASS/FAIL report in the log |

### Specifications

| | Description |
|---|---|
| S1 | Static DiD, 1–31 March, station and day fixed effects |
| S2 | Event study relative to the average January–February gap |
| S3, S3p | As S2, with Italy × lagged Brent (S3) or product prices (S3p), lags estimated on January–February only |
| S4, S4p | Imputation: cost lags estimated on 1 January – 21 March |
| S5 | Imputation with a linear Italian trend estimated on 1–21 March |
| S6 | Quiet periods: 1 Jan – 23 Feb vs 10 Apr – 30 Jun, continuous tax cut |
| S7 | French rebate of 1 April, Italy as control |

Standard errors are clustered by Italian province and French department (205 clusters). Since treatment is assigned at the country level, they measure the precision of the average across stations, not the uncertainty about the counterfactual; the latter is addressed by the sensitivity analysis and the comparison across specifications.

## Validation

- **`99_tests.do`** checks that observations are unique, prices are in range, excluded areas and tax-cut dates are coded correctly, Italy has 24 and France 26 days in the 1–26 March window, the sample has 205 clusters, the gap moves as expected around the two policies, and the saved estimates match a reference run and an independent re-estimation. If `output/tables_ref/` exists, it also compares current estimates with that earlier version.
- **`98_simulation_test.do`** builds a panel with the structure of the real data and known pass-through rates (0.80 and 0.95 in Italy, 0.70 and 0.90 in France), then runs the real estimation scripts on it. Under parallel trends, all specifications recover the true rates; with a known Italy-specific linear trend, S5 recovers the true rates and the other specifications are biased by exactly the predicted amount.

To check reproducibility from scratch: copy the project, move `output/tables` to `output/tables_ref`, delete `data/temp`, `data/processed` and the output figures, set all switches to `1` and `FR_REPARSE = 1`, and run the master. Section G of `99_tests.do` then compares the new estimates with the reference ones.

## Limitations

- A single treated country: inference on the counterfactual cannot rely on sampling variation across treated units.
- European wholesale quotations (Platts, ICE gasoil) are not publicly available, so the lagged-cost explanation of the March divergence cannot be tested directly.
- The missing MIMIT files for 15–16 March restrict the pre-announcement window for the sensitivity analysis.
- The announcement on 18 March and the Italy-specific scrutiny of fuel margins coincide with the cut and cannot be separated from it.
- Spillovers through cross-border refuelling are not tested.
- Some tables in the paper (sensitivity analysis, summary across counterfactuals, price changes by fuel) are written by hand from the logs rather than generated by the code.

## Possible extensions

- Germany (Tankerkönig data) as a second daily control group, or a synthetic control from EU countries with weekly data.
- Placebo cut dates in 2019–2023 to calibrate the sensitivity parameters and for design-based inference.
- Heterogeneity by brand and local competition.
- The end of the Italian cut in December 2022 – January 2023, to test for asymmetric pass-through.

## Author

Matteo Pietrangelo
