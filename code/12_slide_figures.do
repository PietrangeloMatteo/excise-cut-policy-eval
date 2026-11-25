/*==============================================================================
  File   : 12_slide_figures.do
  Input  : $PROC/panel_carburanti_2022.dta
  Output : $OUT/figures_en/fig_prices_zoom_petrol.png
           $OUT/figures_en/fig_prices_zoom_diesel.png

  Prezzi medi in Italia e in Francia, 1 marzo - 15 aprile, per benzina e
  gasolio. Serve alla slide sull'evidenza grezza: mostra se la variazione del
  gap viene dall'Italia che scende o dalla Francia che sale.
  Stesso campione delle stime (panel bilanciato, niente autostrade, niente
  prezzi non aggiornati). Le linee verticali: annuncio italiano (18/3, sera),
  taglio italiano (22/3), remise francese (1/4).
  Gli script 01-11 non sono modificati.
==============================================================================*/

global FIGEN "$OUT/figures_en"
capture mkdir "$FIGEN"

use if balanced == 1 & highway != 1 & !stale & !missing(price_c) ///
    & inrange(date, td(01mar2022), td(15apr2022)) ///
    using "$PROC/panel_carburanti_2022.dta", clear
collapse (mean) price_c, by(country fuel date)

forvalues f = 1/2 {
    local fl = cond(`f' == 1, "petrol", "diesel")
    local tl = cond(`f' == 1, "Petrol", "Diesel")
    twoway (connected price_c date if country == 1 & fuel == `f', ///
                lcolor(maroon) mcolor(maroon) msize(small)) ///
           (connected price_c date if country == 2 & fuel == `f', ///
                lcolor(gs6) mcolor(gs6) msize(small) lpattern(dash)), ///
        xline(`=td(18mar2022) + 0.5', lpattern(shortdash) lcolor(gs10)) ///
        xline(`=td(22mar2022) - 0.5', lpattern(dash) lcolor(gs4)) ///
        xline(`=td(01apr2022) - 0.5', lpattern(dash) lcolor(gs10)) ///
        title("`tl': average pump price") ytitle("Euro cents per litre") xtitle("") ///
        xlabel(`=td(01mar2022)'(7)`=td(12apr2022)', format(%tdDD_Mon)) ///
        legend(order(1 "Italy" 2 "France") rows(1) pos(6)) ///
        note("Price at 8:00, balanced estimation sample. Vertical lines: Italian announcement (18 Mar)," ///
             "Italian cut (22 Mar), French rebate (1 Apr). Italian files for 15-16 March are missing.")
    graph export "$FIGEN/fig_prices_zoom_`fl'.png", replace width(2000)
}

di as text "12_slide_figures completato"
