#' File input and basic parameter collection for index calculations and plot generation
#'
#' @param id, character used to specify namespace, see \code{shiny::\link[shiny]{NS}}
#'
#' @return a \code{shiny::\link[shiny]{tagList}} containing UI elements
griddedStep1UI <- function(id) {
  ns <- NS(id)
  return(tagList(
        column(8,
            div("This page allows you to calculate the indices on netCDF files."),
            h4("1. Select input file(s)"),
            wellPanel(
              fileInput(ns("dataFiles"),
              NULL,
              accept      = c("NetCDF", "application/netcdf,application/x-netcdf", ".nc"),
              placeholder = "Select or drop one or more NetCDF files",
              multiple    = TRUE)
            ),
            h4("2. Enter input dataset information"),
            wellPanel(
              textInput(ns("prName"), "Name of precipitation variable:", value = "precip"),
              textInput(ns("txName"), "Name of maximum temperature variable:", value = "tmax"),
              textInput(ns("tnName"), "Name of minimum temperature variable:", value = "tmin")
            ),
            h4("3. Enter output parameters"),
            wellPanel(
              textInput(ns("outputFileNamePattern"),
                "Output filename format (must use CMIP5 filename convention. e.g. 'var_daily_climpact.sample_historical_NA_1991-2010.nc'):",
                value = "var_daily_climpact.sample_historical_NA_1991-2010.nc"),
              textInput(ns("instituteName"), "Enter your institute's name:"),
              textInput(ns("instituteID"), "Enter your institute's ID:"),
              numericInput(ns("baseStart"), "Start year of base period:", value = 1991),
              numericInput(ns("baseEnd"), "End year of base period:", value = 2010)
            ),
            h4("4. Enter other parameters"),
            wellPanel(
              numericInput(ns("nCores"),
                paste0("Number of cores to use (your computer has ", detectCores(), " cores):"),
                value = 1, min = 1, max = detectCores()),
              h5(strong("Indices à calculer")),
              p("Sélectionnez les indices souhaités. Si aucun n'est coché, tous les indices seront calculés."),
              div(style = "margin-bottom: 10px;",
                actionButton(ns("griddedSelectAll"),   "Tout sélectionner",   class = "btn btn-xs btn-default"),
                actionButton(ns("griddedDeselectAll"), "Tout désélectionner", class = "btn btn-xs btn-default", style = "margin-left: 8px;")
              ),
              fluidRow(
                column(3,
                  h6(strong("Température — seuils simples")),
                  checkboxGroupInput(ns("griddedIndices"), label = NULL,
                    choices = c("fd","id","su","tr","tnlt2","tnltm2","tnltm20","txge30","txge35","tmge5","tmlt5","tmge10","tmlt10"),
                    selected = c()
                  ),
                  h6(strong("Température — statistiques")),
                  checkboxGroupInput(ns("griddedIndices2"), label = NULL,
                    choices = c("txx","tnn","tnx","txn","dtr","tx95t","tmm","txm","tnm"),
                    selected = c()
                  )
                ),
                column(3,
                  h6(strong("Température — percentiles")),
                  checkboxGroupInput(ns("griddedIndices3"), label = NULL,
                    choices = c("tx10p","tx90p","tn10p","tn90p","txgt50p"),
                    selected = c("tx90p","tn10p")
                  ),
                  h6(strong("Température — durées/vagues")),
                  checkboxGroupInput(ns("griddedIndices4"), label = NULL,
                    choices = c("wsdi","wsdid","csdi","csdid","txdtnd","txbdtnbd","gsl","hw"),
                    selected = c()
                  ),
                  h6(strong("Degrés-jours")),
                  checkboxGroupInput(ns("griddedIndices5"), label = NULL,
                    choices = c("hddheatn","cddcoldn","gddgrown"),
                    selected = c()
                  )
                ),
                column(3,
                  h6(strong("Précipitations")),
                  checkboxGroupInput(ns("griddedIndices6"), label = NULL,
                    choices = c("cdd","cwd","r10mm","r20mm","rx1day","rx5day","rxdday","rnnmm","prcptot","sdii","r95p","r99p","r95ptot","r99ptot"),
                    selected = c()
                  )
                ),
                column(3,
                  h6(strong("Sécheresse")),
                  checkboxGroupInput(ns("griddedIndices7"), label = NULL,
                    choices = c("spei","spi"),
                    selected = c("spei")
                  )
                )
              ),
              fileInput(ns("thresholdFiles"),
                NULL,
                accept      = c("NetCDF", "application/netcdf,application/x-netcdf", ".nc"),
                placeholder = "Select or drop one or more threshold files",
                multiple    = TRUE),
              selectInput(ns("ehfDefinition"), label = ("Select EHF calculation: "),
                choices=list("Perkins & Alexander (2013)" = "PA13", "Nairn & Fawcett (2013)" = "NF13"), selected = 1),
              textInput(ns("maxVals"), "Number of data values to process at once (do not change unless you know what you are doing):", value = 10)
            ),
            div(style = "margin-top: 3em; display: block;"),
                actionBttn(ns("calculateGriddedIndices"),
                label = "Calculate NetCDF Indices", style = "jelly", color = "warning", icon = icon("play-circle", "fa-2x")
            )
        ),
      column(4, class = "instructions",
      box(title = "Instructions", width = 12,
        h4("1. Select input file(s)"),
        tags$p("Select the netCDF file with the daily maximum and minimum temperatures and daily precipitation. "),
        tags$p("You are not required to include all three variables in this file. ",
        "Climpact will only calculate indices that use the provided variables and the variables can be stored in separate files.<br />",
        "To provide separate files, you can select multiple files by holding CTRL and clicking the left-mouse button when the dialog box appears."),
        h4("2. Enter input dataset information"),
        tags$p("You will need to provide the names of the three variables as they are stored in the provided input file(s)."),
        h4("3. Enter output parameters"),
        tags$p("The output filename convention should also be specified - this must follow CMIP5 conventions like the default provided."),
        tags$p("Institute name and ID are required for metadata."),
        tags$p("The base period start and end years are required."),
        h4("4. Enter other parameters"),
        tags$p("The number of computer cores to use can be modified from the default of 1."),
        tags$p("If you wish to choose which indices to calculate, enter these, otherwise leave blank to calculate all."),
        tags$p("Optionally, select a threshold file that will be used for thresholds rather than calculating thresholds from the input file.<br />",
          " You might want to do this if you wish to calculate gridded indices based on future climate simulations",
          " using thresholds calculated from historical simulations."),
        tags$p("The type of Excess Heat Factor (EHF) calculation can be chosen. You should not change this unless you are familiar with the EHF."),
        tags$p("It is possible to change the number of data values to process at once, but do not change this unless you know what you are doing."),
        h4("Calculate"),
        tags$p("Click the 'Calculate NetCDF Indices' button. ",
          "If you have provided all the required information as described above, ",
          "a dialog box will appear reminding you that calcuating gridded indices usually takes a long time.<br />",
          "Once you select 'Calculate Indices' processing will commence.<br />",
          "If you are unsure, click 'Cancel' to return to this screen."),
        conditionalPanel(
            condition = "output.ncdfCalculationStatusText != 'Not Started'",
            ns = ns,
            HTML("<div class= 'alert alert-info' role='alert'>
              <span class='glyphicon glyphicon-exclamation-sign' aria-hidden='true'>
              </span><span class='sr-only'></span>"),
            uiOutput(ns("ncGriddedDone")),
            HTML("</div>")
        )
      )
    )
  ))
}