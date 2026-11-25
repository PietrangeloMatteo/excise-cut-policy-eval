/*==============================================================================
  Progetto : Pass-through del taglio delle accise sui carburanti
             (Italia, 22 marzo 2022) - DiD Italia vs Francia
  File     : 00_master.do
  Scopo    : imposta percorsi e parametri, crea le cartelle, lancia i do-file
  Requisiti: Stata 16 o successivo con integrazione Python configurata
             (serve solo per leggere l'XML francese in 02_clean_france.do)

  Struttura attesa delle cartelle:
    ROOT/
      code/            <- questi do-file
      data/raw/        <- dati originali (già presente)
        2022_1_tr_price/   prezzo_alle_8-20220101.csv ... 20220331.csv
        2022_2_tr_price/   prezzo_alle_8-20220401.csv ... 20220630.csv
        2022_1_tr-an/      anagrafica_impianti_attivi-20220101.csv ...
        2022_2_tr-an/      anagrafica_impianti_attivi-20220401.csv ...
        PrixCarburants_annuel_2022.xml   (file o cartella che contiene l'xml)
        DCOILBRENTEU.csv, DEXUSEU.csv    (FRED, obbligatori per le stime)
        DGASNYH.csv, DDFUELNYH.csv       (FRED, facoltativi)
      data/temp/       <- file intermedi (creata qui)
      data/processed/  <- dataset finale su cui si lavora (creata qui)
      output/figures/  output/tables/  logs/   (create qui)
==============================================================================*/

version 16
clear all
set more off
set varabbrev off

*------------------------------------------------------------------------------
* 1. Percorso radice del progetto  >>> MODIFICA QUI <<<
*------------------------------------------------------------------------------
global ROOT "/Users/pietrangelomatteo/Desktop/gas-prices-IT-FR"

*------------------------------------------------------------------------------
* 2. Cartelle
*------------------------------------------------------------------------------
global DATA "$ROOT/data"
global RAW  "$DATA/raw"
global TEMP "$DATA/temp"
global PROC "$DATA/processed"
global CODE "$ROOT/code"
global OUT  "$ROOT/output"
global FIG  "$OUT/figures"
global TAB  "$OUT/tables"
global LOGS "$ROOT/logs"

foreach d in "$CODE" "$TEMP" "$TEMP/it_prezzi" "$TEMP/it_anagrafica" ///
             "$PROC" "$OUT" "$FIG" "$TAB" "$LOGS" {
    capture mkdir "`d'"
}

* controllo che i dati grezzi siano dove ci aspettiamo
capture confirm file "$RAW/2022_1_tr_price/prezzo_alle_8-20220101.csv"
if _rc {
    di as error "Non trovo i csv MIMIT in $RAW/2022_1_tr_price: controlla global ROOT."
    exit 601
}

*------------------------------------------------------------------------------
* 3. Parametri del disegno
*------------------------------------------------------------------------------
* Date chiave
global T0_IT = td(22mar2022)   // entrata in vigore del taglio italiano (DL 21/2022)
global T0_FR = td(01apr2022)   // inizio della "remise carburant" francese
* Entità dei tagli, centesimi/litro IVA inclusa
global CUT_IT = 30.5           // 25 cent di accisa x 1,22 (IVA)
global CUT_FR = 18             // 15 cent HT x 1,20 (IVA), Francia continentale

* Periodo coperto dal dataset processed
global PANEL_START = td(01jan2022)
global PANEL_END   = td(30jun2022)

* Finestra principale di stima: la Francia è un controllo pulito fino a fine marzo.
* Dal 27/3 i distributori francesi potevano già vendere carburante scontato alle
* stazioni, quindi per prudenza la finestra si chiude il 26/3.
global WIN_START = td(01mar2022)
global WIN_END   = td(26mar2022)
* Fine della finestra per le stime: i grafici mostrano che i prezzi francesi
* non si muovono prima del 1/4, quindi si può arrivare al 31/3.
* (WIN_END resta al 26/3 perché definisce il campione bilanciato in 03.)
global EST_END   = td(31mar2022)

* Scelte di campione
global IT_SELF   = 1        // 1 = solo prezzi self service in Italia
global FR_PETROL "SP95"     // benzina francese di confronto: SP95 = E5, come la benzina
                            // italiana. Alternativa: "E10" (SP95-E10, più diffusa in FR)
global STALE_MAX = 30       // prezzo considerato vecchio se non aggiornato da > N giorni
global PMIN      = 1.0      // prezzi fuori da [PMIN, PMAX] euro/l trattati come errori
global PMAX      = 3.0

* Rileggere l'XML francese anche se il csv intermedio esiste già (lento)
global FR_REPARSE = 0

*------------------------------------------------------------------------------
* 4. Interruttori: 1 = esegui, 0 = salta
*------------------------------------------------------------------------------
global RUN_IT    = 0
global RUN_FR    = 0
global RUN_PANEL = 0
global RUN_VIZ   = 0
global RUN_COSTS = 0     // serie FRED: Brent, cambio, prodotti NY Harbor
global RUN_EST   = 0     // stime
global RUN_HD    = 0     // event study rif. 21/3 e analisi di sensibilità honestdid
global RUN_PAPER = 0     // figure in inglese e tabelle LaTeX per il paper
global RUN_ANN   = 0     // event study con riferimento 18 marzo (annuncio) e verifica cluster
global RUN_TESTS = 0     // controlli automatici su dati, stime e output
global RUN_SIM   = 0     // simulazione: il codice recupera un pass-through noto?
global RUN_DCHECK = 0     // verifica: il rialzo del gasolio francese e' uno shock comune?
global RUN_PLACEBO = 0     // inferenza placebo nel tempo
global RUN_SLIDEFIG = 1		// Grafico dei prezzi Italia e Francia

*------------------------------------------------------------------------------
* 5. Esecuzione
*------------------------------------------------------------------------------
capture log close
log using "$LOGS/00_master.log", replace text

if $RUN_FR == 1 {
    capture python query
    if _rc {
        di as error "Integrazione Python non disponibile: serve per l'XML francese."
        di as error "Configura Python con -set python_exec- oppure vedi -help python-."
        exit 198
    }
}

if $RUN_IT    == 1 do "$CODE/01_clean_italy.do"
if $RUN_FR    == 1 do "$CODE/02_clean_france.do"
if $RUN_PANEL == 1 do "$CODE/03_build_panel.do"
if $RUN_VIZ   == 1 do "$CODE/04_visualization.do"
if $RUN_COSTS == 1 do "$CODE/05_clean_costs.do"
if $RUN_EST   == 1 do "$CODE/06_estimation.do"
if $RUN_HD    == 1 do "$CODE/07_honestdid.do"
if $RUN_PAPER == 1 do "$CODE/08_paper_outputs.do"
if $RUN_ANN   == 1 do "$CODE/09_announcement.do"
if $RUN_SIM   == 1 do "$CODE/98_simulation_test.do"
if $RUN_TESTS == 1 do "$CODE/99_tests.do"
if $RUN_DCHECK == 1 do "$CODE/10_diesel_check.do"
if $RUN_PLACEBO == 1 do "$CODE/11_placebo.do"
if $RUN_SLIDEFIG == 1 do "$CODE/12_slide_figures.do"

log close
