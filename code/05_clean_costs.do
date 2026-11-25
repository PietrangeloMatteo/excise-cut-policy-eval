/*==============================================================================
  File   : 05_clean_costs.do
  Input  (da FRED, csv, in $RAW):
           DCOILBRENTEU.csv  Brent, dollari/barile                (obbligatorio)
           DEXUSEU.csv       dollari per 1 euro                    (obbligatorio)
           DGASNYH.csv       benzina New York Harbor, $/gallone    (facoltativo)
           DDFUELNYH.csv     gasolio ULSD New York Harbor, $/gallone (facoltativo)
  Output : $PROC/costi_daily.dta  (un'osservazione per giorno di calendario)
  Note   : - nei weekend e festivi porto avanti l'ultima quotazione disponibile;
           - tutto convertito in centesimi di euro per litro, al netto delle tasse
             (1 barile = 158,987 l; 1 gallone = 3,78541 l);
           - ritardi raggruppati in tre blocchi (giorno precedente, media 2-7 giorni,
             media 8-14 giorni) per non stimare troppi parametri con pochi giorni:
             la quotazione di chiusura del giorno d-1 è nota alle 8:00 del giorno d.
==============================================================================*/

*------------------------------------------------------------------------------
* Programma: legge un csv FRED (colonna 1 = data, colonna 2 = valore).
* Funziona sia con l'intestazione "DATE" sia con "observation_date" e tratta
* "." o vuoto come giorno senza quotazione.
*------------------------------------------------------------------------------
capture program drop fred_read
program define fred_read
    syntax using/, gen(name)
    import delimited using "`using'", varnames(1) stringcols(_all) clear
    unab vars : _all
    local vd : word 1 of `vars'
    local vv : word 2 of `vars'
    gen date = date(`vd', "YMD")
    destring `vv', gen(`gen') force
    keep date `gen'
    drop if missing(date)
    format date %td
end

*------------------------------------------------------------------------------
* Programma: blocchi di ritardi per una serie giornaliera (dati già tsset)
*------------------------------------------------------------------------------
capture program drop make_bins
program define make_bins
    args v
    gen double `v'_l1 = L1.`v'
    gen double `v'_l2_7 = 0
    forvalues l = 2/7 {
        replace `v'_l2_7 = `v'_l2_7 + L`l'.`v' / 6
    }
    gen double `v'_l8_14 = 0
    forvalues l = 8/14 {
        replace `v'_l8_14 = `v'_l8_14 + L`l'.`v' / 7
    }
    label var `v'_l1    "`v': giorno precedente"
    label var `v'_l2_7  "`v': media ritardi 2-7 giorni"
    label var `v'_l8_14 "`v': media ritardi 8-14 giorni"
end

*------------------------------------------------------------------------------
* Import e unione delle serie
*------------------------------------------------------------------------------
tempfile base
fred_read using "$RAW/DEXUSEU.csv", gen(usd_per_eur)
save `base'

fred_read using "$RAW/DCOILBRENTEU.csv", gen(brent_usd)
merge 1:1 date using `base', nogen
save `base', replace

local series "usd_per_eur brent_usd"
capture confirm file "$RAW/DGASNYH.csv"
if !_rc {
    fred_read using "$RAW/DGASNYH.csv", gen(gas_usd)
    merge 1:1 date using `base', nogen
    save `base', replace
    local series "`series' gas_usd"
}
capture confirm file "$RAW/DDFUELNYH.csv"
if !_rc {
    fred_read using "$RAW/DDFUELNYH.csv", gen(ulsd_usd)
    merge 1:1 date using `base', nogen
    save `base', replace
    local series "`series' ulsd_usd"
}
use `base', clear

*------------------------------------------------------------------------------
* Calendario completo e riempimento dei giorni senza quotazione
*------------------------------------------------------------------------------
tsset date
tsfill
sort date
foreach v of local series {
    replace `v' = `v'[_n-1] if missing(`v')
}

*------------------------------------------------------------------------------
* Conversione in centesimi di euro per litro e ritardi
*------------------------------------------------------------------------------
gen double brent = brent_usd / usd_per_eur / 158.987 * 100
label var brent "Brent, centesimi di euro/l"
local costs "brent"

capture confirm variable gas_usd
if !_rc {
    gen double gas = gas_usd / usd_per_eur / 3.78541 * 100
    label var gas "Benzina NY Harbor, centesimi di euro/l"
    local costs "`costs' gas"
}
capture confirm variable ulsd_usd
if !_rc {
    gen double ulsd = ulsd_usd / usd_per_eur / 3.78541 * 100
    label var ulsd "Gasolio ULSD NY Harbor, centesimi di euro/l"
    local costs "`costs' ulsd"
}

tsset date
foreach c of local costs {
    make_bins `c'
}

keep if inrange(date, $PANEL_START - 30, $PANEL_END)

* controllo di copertura: i ritardi devono esistere dall'inizio del panel
local ok_costs ""
foreach c of local costs {
    quietly count if missing(`c'_l8_14) & date >= $PANEL_START
    if r(N) == 0 {
        local ok_costs "`ok_costs' `c'"
        continue
    }
    if "`c'" == "brent" {
        di as error "Brent: ritardi mancanti dopo l'inizio del panel."
        di as error "Scarica DCOILBRENTEU e DEXUSEU almeno dal 1/11/2021."
        exit 459
    }
    di as error "`c': copertura incompleta, serie esclusa dalle stime."
    drop `c' `c'_l1 `c'_l2_7 `c'_l8_14
}
local costs "`ok_costs'"

di as text "Serie di costo disponibili: `costs'"
compress
save "$PROC/costi_daily.dta", replace
