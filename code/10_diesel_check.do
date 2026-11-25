/*==============================================================================
  File   : 10_diesel_check.do
  Input  : $PROC/panel_carburanti_2022.dta, $PROC/costi_daily.dta
  Output : $TAB/diesel_check_changes.dta / .csv   variazioni 21->24 e 21->31
           $TAB/diesel_check_did.dta / .csv       DiD al giorno +2 per gruppo di controllo
           $TAB/tab_diesel_check.tex              tabella per il paper
           $OUT/figures_en/fig_diesel_check_<fuel>.png

  Domanda: dopo il 22 marzo il gasolio francese sale (circa +6 c tra il 21 e il
  24), la benzina francese no. Se il rialzo è uno shock specifico della Francia,
  la Francia non rappresenta il controfattuale italiano e il pass-through del
  gasolio è sovrastimato. Due verifiche:

  1. Shock globale sul gasolio? Confronto con le quotazioni all'ingrosso
     di New York (benzina e gasolio ULSD, FRED). Se il gasolio all'ingrosso
     rincara rispetto alla benzina negli stessi giorni, il rialzo francese è
     coerente con uno shock comune sul prodotto, che avrebbe colpito anche
     l'Italia senza taglio.
     Allineamento: il prezzo alla pompa delle 8:00 del giorno t può riflettere
     al massimo la chiusura di New York del giorno t-1, quindi la quotazione è
     ritardata di un giorno.

  2. Shock specifico del Nord Europa? La Francia del Nord si rifornisce
     soprattutto dall'area di Rotterdam, la Francia mediterranea dalle
     raffinerie e dai depositi del Mediterraneo (Fos-Lavéra), la stessa area di
     quotazione dell'Italia (CIF Med). Se il rialzo francese del gasolio dipende
     da un allargamento del differenziale Rotterdam-Mediterraneo, deve essere
     più debole nella Francia mediterranea, e il DiD con solo la Francia
     mediterranea come controllo deve dare un pass-through più basso.
     Francia mediterranea = dipartimenti delle regioni Provence-Alpes-Côte
     d'Azur e Occitanie (Corsica già esclusa).

  Il DiD al giorno +2 è calcolato come differenza tra le variazioni medie per
  distributore dal 21 al 24 marzo (Italia meno controllo). Sul panel bilanciato
  coincide con il coefficiente dell'event study per k = 2 con riferimento 21
  marzo. Errori standard clusterizzati per provincia / dipartimento.

  Le specificazioni S1-S7 e gli script 01-09 non sono modificati.
==============================================================================*/

global FIGEN "$OUT/figures_en"
capture mkdir "$FIGEN"

local d18 = td(18mar2022)
local d21 = td(21mar2022)
local d24 = td(24mar2022)
local d31 = td(31mar2022)

* dipartimenti della Francia mediterranea (PACA + Occitanie)
local med_deps "04 05 06 13 83 84 09 11 12 30 31 32 34 46 48 65 66 81 82"

*------------------------------------------------------------------------------
* 0. Dati alla pompa: campione principale, panel bilanciato
*------------------------------------------------------------------------------
use if balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
    & inrange(date, td(10mar2022), $EST_END) using "$PROC/panel_carburanti_2022.dta", clear
keep unit_id country italy region fuel date price_c

gen byte fr_med = 0
foreach d of local med_deps {
    quietly replace fr_med = 1 if country == 2 & region == "`d'"
}
gen byte grp = cond(country == 1, 1, cond(fr_med == 1, 2, 3))
label define grp 1 "Italy" 2 "France, Mediterranean" 3 "France, rest"
label values grp grp

di as text "Distributori per gruppo e carburante (21 marzo):"
tab grp fuel if date == `d21'

tempfile pump
save `pump'

*------------------------------------------------------------------------------
* 1. Quotazioni all'ingrosso, ritardate di un giorno
*------------------------------------------------------------------------------
use "$PROC/costi_daily.dta", clear
local have_ws = 1
foreach v in gas ulsd {
    capture confirm variable `v'
    if _rc {
        di as error "`v' non trovato in costi_daily.dta: verifica 1 saltata."
        local have_ws = 0
    }
}
if `have_ws' {
    keep date gas ulsd
    tsset date
    gen double ws1 = L1.gas
    gen double ws2 = L1.ulsd
    keep date ws1 ws2
    reshape long ws, i(date) j(fuel)
    tempfile ws
    save `ws'
}

*------------------------------------------------------------------------------
* 2. Medie giornaliere e variazioni rispetto al 21 marzo
*------------------------------------------------------------------------------
use `pump', clear
collapse (mean) price_c, by(grp fuel date)
reshape wide price_c, i(fuel date) j(grp)
rename (price_c1 price_c2 price_c3) (p_it p_frmed p_frrest)

* media francese complessiva, pesata per numero di distributori
preserve
    use `pump', clear
    keep if country == 2
    collapse (mean) p_fr = price_c, by(fuel date)
    tempfile fr
    save `fr'
restore
merge 1:1 fuel date using `fr', nogen
if `have_ws' merge 1:1 fuel date using `ws', keep(master match) nogen
else gen double ws = .

sort fuel date
foreach v in ws p_fr p_frmed p_frrest p_it {
    bysort fuel: egen double base21 = max(cond(date == `d21', `v', .))
    gen double c_`v' = `v' - base21
    drop base21
}
label var c_ws      "Wholesale, NY Harbor (previous-day close)"
label var c_p_fr    "France, pump price"
label var c_p_frmed "France, Mediterranean"
label var c_p_frrest "France, rest"
label var c_p_it    "Italy, pump price"

* figure: variazione cumulata dal 21 marzo
foreach f in 1 2 {
    local fl = cond(`f' == 1, "petrol", "diesel")
    local tl = proper("`fl'")
    local wsplot ""
    local leg `"1 "France, Mediterranean" 2 "France, rest" 3 "Italy""'
    if `have_ws' {
        local wsplot "(line c_ws date if fuel == `f', lcolor(gs8) lpattern(dash) lwidth(medthick))"
        local leg `"1 "Wholesale, NY Harbor (lagged 1 day)" 2 "France, Mediterranean" 3 "France, rest" 4 "Italy""'
    }
    twoway `wsplot' ///
        (line c_p_frmed  date if fuel == `f', lcolor(ebblue) lwidth(medthick)) ///
        (line c_p_frrest date if fuel == `f', lcolor(navy) lpattern(shortdash) lwidth(medthick)) ///
        (line c_p_it     date if fuel == `f', lcolor(dkgreen) lwidth(medthick)), ///
        xline(`=td(22mar2022) - 0.5', lpattern(dash) lcolor(gs6)) yline(0, lcolor(gs12)) ///
        title("`tl': change since 21 March") ytitle("Cents per litre") xtitle("") ///
        xlabel(`=td(10mar2022)'(7)`=td(31mar2022)', format(%tdDD_Mon)) ///
        legend(order(`leg') rows(2) size(small)) ///
        note("Pump prices at 8:00, balanced sample. Wholesale quotation of the previous day," ///
             "converted to euro cents per litre. Dashed vertical line: Italian cut.")
    graph export "$FIGEN/fig_diesel_check_`fl'.png", replace width(2000)
}

* tabella delle variazioni: 18->21, 21->24, 21->31
keep fuel date c_ws c_p_fr c_p_frmed c_p_frrest c_p_it
keep if inlist(date, `d18', `d21', `d24', `d31')
reshape long c_, i(fuel date) j(series) string
rename c_ change
reshape wide change, i(series date) j(fuel)
rename (change1 change2) (petrol diesel)
gen double diff = diesel - petrol
gen str8 window = ""
replace window = "18to21" if date == `d18'
replace window = "21to24" if date == `d24'
replace window = "21to31" if date == `d31'
* per il 18 marzo la variazione 18->21 è il segno opposto del livello relativo al 21
foreach v in petrol diesel diff {
    replace `v' = -`v' if window == "18to21"
}
drop if window == ""
drop date
order series window petrol diesel diff
sort series window
list, sepby(series) noobs
save "$TAB/diesel_check_changes.dta", replace
export delimited using "$TAB/diesel_check_changes.csv", replace

*------------------------------------------------------------------------------
* 3. DiD al giorno +2 con controlli diversi
*------------------------------------------------------------------------------
tempname P
postfile `P' str8 fuel str24 control double(b se passthrough pt_se) long(n_it n_ctrl) ///
    using "$TAB/diesel_check_did.dta", replace

forvalues f = 1/2 {
    local fl = cond(`f' == 1, "petrol", "diesel")
    use if fuel == `f' & inlist(date, `d21', `d24') using `pump', clear
    reshape wide price_c, i(unit_id) j(date)
    gen double dp = price_c`d24' - price_c`d21'
    drop if missing(dp)
    egen long cl = group(grp region), missing

    foreach ctl in all med rest {
        if "`ctl'" == "all"  local cond "inlist(grp, 1, 2, 3)"
        if "`ctl'" == "med"  local cond "inlist(grp, 1, 2)"
        if "`ctl'" == "rest" local cond "inlist(grp, 1, 3)"
        quietly reg dp italy if `cond', vce(cluster cl)
        local b  = _b[italy]
        local se = _se[italy]
        quietly count if `cond' & italy == 1
        local nit = r(N)
        quietly count if `cond' & italy == 0
        local nct = r(N)
        post `P' ("`fl'") ("`ctl'") (`b') (`se') (-`b' / $CUT_IT) (`se' / $CUT_IT) (`nit') (`nct')
        di as text "`fl' - controllo `ctl': effetto " %6.2f `b' " (" %4.2f `se' ///
            "), pass-through " %5.3f (-`b' / $CUT_IT) ", N controllo = `nct'"
    }
}
postclose `P'

use "$TAB/diesel_check_did.dta", clear
list, sepby(fuel) noobs
export delimited using "$TAB/diesel_check_did.csv", replace

*------------------------------------------------------------------------------
* 4. Tabella LaTeX
*------------------------------------------------------------------------------
* Pannello A: variazioni 21->24 marzo
use "$TAB/diesel_check_changes.dta", clear
keep if window == "21to24"
gen byte ord = .
replace ord = 1 if series == "ws"
replace ord = 2 if series == "p_fr"
replace ord = 3 if series == "p_frmed"
replace ord = 4 if series == "p_frrest"
replace ord = 5 if series == "p_it"
sort ord
tempname T
file open `T' using "$TAB/tab_diesel_check.tex", write replace
file write `T' "\begin{tabular}{lccc}" _n "\toprule" _n
file write `T' "\multicolumn{4}{l}{\textit{A. Change in average price, 21 to 24 March (cents/l)}} \\" _n
file write `T' " & Petrol & Diesel & Diesel $-$ petrol \\" _n "\midrule" _n
forvalues r = 1/`=_N' {
    local s = series[`r']
    if "`s'" == "ws"       local lab "Wholesale, NY Harbor (previous-day close)"
    if "`s'" == "p_fr"     local lab "France, all stations"
    if "`s'" == "p_frmed"  local lab "\quad France, Mediterranean"
    if "`s'" == "p_frrest" local lab "\quad France, rest"
    if "`s'" == "p_it"     local lab "Italy"
    if missing(petrol[`r']) & "`s'" == "ws" continue
    file write `T' "`lab' & " %5.1f (petrol[`r']) " & " %5.1f (diesel[`r']) " & " %5.1f (diff[`r']) " \\" _n
}

* Pannello B: DiD al giorno +2
use "$TAB/diesel_check_did.dta", clear
file write `T' "\addlinespace" _n "\midrule" _n
file write `T' "\multicolumn{4}{l}{\textit{B. Pass-through on 24 March by control group}} \\" _n
file write `T' "Control group & Petrol & Diesel & \\" _n "\midrule" _n
foreach ctl in all med rest {
    if "`ctl'" == "all"  local lab "France, all stations"
    if "`ctl'" == "med"  local lab "France, Mediterranean"
    if "`ctl'" == "rest" local lab "France, rest"
    file write `T' "`lab'"
    foreach fl in petrol diesel {
        quietly summarize passthrough if fuel == "`fl'" & control == "`ctl'"
        local pt = r(mean)
        quietly summarize pt_se if fuel == "`fl'" & control == "`ctl'"
        file write `T' " & " %5.3f (`pt') " (" %5.3f (r(mean)) ")"
    }
    file write `T' " & \\" _n
}
file write `T' "\addlinespace" _n "French stations"
foreach ctl in med rest {
    foreach fl in petrol diesel {
        quietly summarize n_ctrl if fuel == "`fl'" & control == "`ctl'"
        local n_`ctl'_`fl' = r(mean)
    }
}
file write `T' " (Med.\ / rest) & " %9.0fc (`n_med_petrol') " / " %9.0fc (`n_rest_petrol') ///
    " & " %9.0fc (`n_med_diesel') " / " %9.0fc (`n_rest_diesel') " & \\" _n
file write `T' "\bottomrule" _n "\end{tabular}" _n
file close `T'

di as text _n "10_diesel_check completato: $TAB/tab_diesel_check.tex"
