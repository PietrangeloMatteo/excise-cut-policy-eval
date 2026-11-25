/*==============================================================================
  File   : 04_visualization.do
  Input  : $PROC/panel_carburanti_2022.dta
  Output : grafici in $FIG
    01_prezzo_medio_<f>.png    prezzo medio IT vs FR, gen-giu 2022
    02_differenza_IT_FR.png    differenza IT - FR, gen-giu 2022
    03_differenza_zoom.png     differenza IT - FR, 1 marzo - 15 aprile
    04_n_impianti.png          impianti osservati per giorno (qualità dati)
    05_quota_variazioni.png    quota di impianti che cambiano prezzo ogni giorno
    06_dprezzo_impianto_<f>.png  distribuzione della variazione di prezzo per
                                 impianto tra il 21/3 e il 25/3
    07_giorni_ultimo_agg.png   giorni dall'ultimo aggiornamento al 21/3
  Linee verticali: tratteggio scuro = taglio IT (22/3); chiaro = remise FR (1/4)
==============================================================================*/

set scheme s1color
local xl "xline($T0_IT, lpattern(dash) lcolor(gs5)) xline($T0_FR, lpattern(shortdash) lcolor(gs11))"
local xlab_full `"xlabel(`=td(01jan2022)'(14)`=td(30jun2022)', format(%tdDD/NN) angle(45))"'
local xlab_zoom `"xlabel(`=td(01mar2022)'(5)`=td(15apr2022)', format(%tdDD/NN) angle(45))"'

use "$PROC/panel_carburanti_2022.dta", clear
keep if highway != 1 & !stale & !missing(price_c) & balanced == 1

*------------------------------------------------------------------------------
* Medie giornaliere per paese e carburante
*------------------------------------------------------------------------------
preserve
collapse (mean) price_c changed (count) n = price_c, by(country fuel date)

* 01 - prezzo medio
forvalues f = 1/2 {
    local fl : label fuel `f'
    twoway (line price_c date if country == 1 & fuel == `f', lcolor(navy)) ///
           (line price_c date if country == 2 & fuel == `f', lcolor(maroon)), ///
        `xl' `xlab_full' ///
        title("`fl': prezzo medio alla pompa") ///
        ytitle("centesimi/litro") xtitle("") ///
        legend(order(1 "Italia" 2 "Francia") rows(1) pos(6))
    graph export "$FIG/01_prezzo_medio_`f'.png", replace width(2000)
}

* 04 - numero di impianti osservati
twoway (line n date if country == 1 & fuel == 1, lcolor(navy)) ///
       (line n date if country == 2 & fuel == 1, lcolor(maroon)), ///
    `xl' `xlab_full' title("Impianti osservati per giorno (benzina)") ///
    ytitle("numero di impianti") xtitle("") ///
    legend(order(1 "Italia" 2 "Francia") rows(1) pos(6))
graph export "$FIG/04_n_impianti.png", replace width(2000)

* 05 - quota di impianti che cambiano prezzo
forvalues f = 1/2 {
    local fl : label fuel `f'
    twoway (connected changed date if country == 1 & fuel == `f', lcolor(navy) mcolor(navy) msize(small)) ///
           (connected changed date if country == 2 & fuel == `f', lcolor(maroon) mcolor(maroon) msize(small)) ///
           if inrange(date, td(01mar2022), td(15apr2022)), ///
        `xl' `xlab_zoom' title("`fl': quota di impianti che cambiano prezzo") ///
        ytitle("quota") xtitle("") ///
        legend(order(1 "Italia" 2 "Francia") rows(1) pos(6))
    graph export "$FIG/05_quota_variazioni_`f'.png", replace width(2000)
}

* 02-03 - differenza Italia - Francia
keep country fuel date price_c
reshape wide price_c, i(fuel date) j(country)
gen diff = price_c1 - price_c2
label var diff "Italia - Francia, centesimi/l"

twoway (line diff date if fuel == 1, lcolor(navy)) ///
       (line diff date if fuel == 2, lcolor(dkorange)), ///
    `xl' `xlab_full' ///
    title("Differenza di prezzo Italia - Francia") ///
    subtitle("Taglio IT = $CUT_IT c/l (22/3); remise FR = $CUT_FR c/l (1/4)") ///
    ytitle("centesimi/litro") xtitle("") ///
    legend(order(1 "Benzina" 2 "Gasolio") rows(1) pos(6))
graph export "$FIG/02_differenza_IT_FR.png", replace width(2000)

twoway (connected diff date if fuel == 1, lcolor(navy) mcolor(navy) msize(small)) ///
       (connected diff date if fuel == 2, lcolor(dkorange) mcolor(dkorange) msize(small)) ///
       if inrange(date, td(01mar2022), td(15apr2022)), ///
    `xl' `xlab_zoom' ///
    title("Differenza di prezzo Italia - Francia, zoom") ///
    ytitle("centesimi/litro") xtitle("") ///
    legend(order(1 "Benzina" 2 "Gasolio") rows(1) pos(6))
graph export "$FIG/03_differenza_zoom.png", replace width(2000)
restore

*------------------------------------------------------------------------------
* 06 - variazione di prezzo per impianto dal 21/3 (giorno -1) al 25/3 (giorno +3)
*------------------------------------------------------------------------------
gen dp = price_c - L4.price_c if date == $T0_IT + 3
forvalues f = 1/2 {
    local fl : label fuel `f'
    twoway (kdensity dp if italy == 1 & fuel == `f', lcolor(navy)) ///
           (kdensity dp if italy == 0 & fuel == `f', lcolor(maroon)), ///
        xline(-$CUT_IT, lpattern(dash) lcolor(gs5)) ///
        title("`fl': variazione di prezzo per impianto, 21/3 - 25/3") ///
        xtitle("centesimi/litro") ytitle("densità") ///
        note("Linea tratteggiata: taglio italiano con IVA (-$CUT_IT c/l)") ///
        legend(order(1 "Italia" 2 "Francia") rows(1) pos(6))
    graph export "$FIG/06_dprezzo_impianto_`f'.png", replace width(2000)
}

*------------------------------------------------------------------------------
* 07 - giorni dall'ultimo aggiornamento il giorno prima del taglio
*      (sul campione completo, inclusi i prezzi vecchi)
*------------------------------------------------------------------------------
use "$PROC/panel_carburanti_2022.dta", clear
histogram days_since_update if date == $T0_IT - 1 & highway != 1 & ///
    inrange(days_since_update, 0, 60), discrete percent ///
    by(country, title("Giorni dall'ultimo aggiornamento del prezzo, 21/3/2022") note("")) ///
    xtitle("giorni")
graph export "$FIG/07_giorni_ultimo_agg.png", replace width(2000)
