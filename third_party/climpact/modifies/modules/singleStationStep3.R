singleStationStep3 <- function(input, output, session, parentSession, climpactUI, singleStationState) {

  output$indexCalculationErrors <- reactive({
    # trigger refresh on update
    singleStationState$isQCCompleted()
    singleStationState$indexCalculationStatus()
    singleStationState$indexCalculationErrors()
  })
  outputOptions(output, "indexCalculationErrors", suspendWhenHidden = FALSE)

  output$indexCalculationStatus <- reactive({
    # trigger refresh on update
    singleStationState$isQCCompleted()
    singleStationState$indexCalculationStatus()
  })
  outputOptions(output, "indexCalculationStatus", suspendWhenHidden = FALSE)


  output$slickRIndices <- renderSlickR({
    imgs <- list()
    if (!is.null(singleStationState$outputFolders())) {
      watchPath <- singleStationState$outputFolders()$outplotsdir
      imgs <- list.files(watchPath, pattern=".png", full.names = TRUE)
    }
    bottom_opts <- settings(arrows = FALSE, slidesToShow = 5, slidesToScroll = 1, centerMode = TRUE, focusOnSelect = TRUE, initialSlide = 0)
    main <- slickR(imgs, slideId = "slickRIndicesMain", height = 600)
    nav <-  (slickR(imgs, slideId = "slickRIndicesNav", height = 100) + bottom_opts)
    main %synch% nav
  })

  singleStationState$indexCalculationStatus("Not Started")
  folderToZip <- reactiveVal("")
  indicesZipLink <- reactiveVal("")

  observeEvent(singleStationState$metadata(), {
    updateTextInput(session, "plotTitle", value=singleStationState$metadata()$title.station)
  })

  output$qualityControlErrorStep3 <- reactive({
    errorHTML <- ""
    if (singleStationState$qualityControlErrors() != "") {
      errorHTML <- HTML("<br /><div class= 'alert alert-danger' role='alert'>
                        <span class='glyphicon glyphicon-exclamation-sign' aria-hidden='true'></span><span class='sr-only'>Error:</span></div>")
    }
    return(errorHTML)
  })

  # All available index short names grouped by checkbox input ID
  all_indices_by_group <- list(
    selectedIndices  = c("fd","id","su","tr","tnlt2","tnltm2","tnltm20","txge30","txge35","tmge5","tmlt5","tmge10","tmlt10"),
    selectedIndices2 = c("txx","tnn","tnx","txn","dtr","tx95t","tmm","txm","tnm"),
    selectedIndices3 = c("tx10p","tx90p","tn10p","tn90p","txgt50p"),
    selectedIndices4 = c("wsdi","wsdid","csdi","csdid","txdtnd","txbdtnbd","gsl","hw"),
    selectedIndices5 = c("hddheatn","cddcoldn","gddgrown"),
    selectedIndices6 = c("cdd","cwd","r10mm","r20mm","rx1day","rx5day","rxdday","rnnmm","prcptot","sdii","r95p","r99p","r95ptot","r99ptot"),
    selectedIndices7 = c("spei","spi")
  )

  observeEvent(input$selectAllIndices, {
    for (grp in names(all_indices_by_group)) {
      updateCheckboxGroupInput(session, grp, selected = all_indices_by_group[[grp]])
    }
  })

  observeEvent(input$deselectAllIndices, {
    for (grp in names(all_indices_by_group)) {
      updateCheckboxGroupInput(session, grp, selected = character(0))
    }
  })

  output$loadParamHelpText <- renderUI({
      indexParamLink <- paste0("<a target=\"_blank\" href=https://github.com/ARCCSS-extremes/climpact/blob/master/www/user_guide/Climpact_user_guide.md#calculatesingle> Section 4.4</a>")
      HTML(paste0("<p>The following fields change user-definable parameters in several Climpact indices.",
                  "<br />Leave as default unless you are interested in these indices. See ",
                  indexParamLink, " of the ", climpactUI$userGuideLink, " for guidance.</p>"))
  })

  # Index calculation has been requested by the user.
  observeEvent(input$calculateIndices, {

    # ------------------------------------------------------------------ #
    # Validate inputs
    # ------------------------------------------------------------------ #
    # Gather all selected indices across all checkbox groups
    selected_indices <- c(
      input$selectedIndices,
      input$selectedIndices2,
      input$selectedIndices3,
      input$selectedIndices4,
      input$selectedIndices5,
      input$selectedIndices6,
      input$selectedIndices7
    )

    validate(
        need(input$plotTitle != "", message = "Please enter a plot title"),
        need(length(selected_indices) > 0, message = "Please select at least one index to calculate."),
        need(input$wsdin <= 10, message = "WSDId: value must be between 1 and 10"),
        need(input$wsdin > 0, message = "WSDId: value must be between 1 and 10"),
        need(input$csdin <= 10, message = "CSDId: value must be between 1 and 10"),
        need(input$csdin > 0, message = "CSDId: value must be between 1 and 10"),
        need(input$rxnday >= 1, message = "RXnDAY: value must be a positive number"),
        need(input$txtn >= 1, message = "TXdTNd and TXbdTNbd: value must be a positive number"),
        need(input$rnnmm >= 0, message = "Rnnmm: value must be greater than or equal to zero"),
        need(input$spei >= 1, message = "Custom SPEI/SPI time scale value must be a positive number")
    )

    disable("calculateIndices")

    params <- climdexInputParams(wsdi_ud          = input$wsdin,
                                  csdi_ud         = input$csdin,
                                  rx_ud           = input$rxnday,
                                  txtn_ud         = input$txtn,
                                  Tb_HDD          = input$hdd,
                                  Tb_CDD          = input$cdd,
                                  Tb_GDD          = input$gdd,
                                  rnnmm_ud        = input$rnnmm,
                                  custom_SPEI     = input$spei,
                                  var.choice      = input$custVariable,
                                  op.choice       = input$custOperation,
                                  constant.choice = input$custThreshold
                                  )
    singleStationState$climdexInputParams(params)

    progress <- shiny::Progress$new()
#    on.exit(progress$close())
    progress$set(message = "Calculating indices", value = 0)

    out <- tryCatch({
       updateCollapse(session, "collapseStep3", close = "Settings")
   
       singleStationState$indexCalculationStatus("In Progress")
   
       index.calc(progress, 2, singleStationState$metadata(),
         singleStationState$climdexInput(), singleStationState$outputFolders(),
         singleStationState$climdexInputParams(),
         selected_indices = selected_indices)
   
       # Create a zip file containing all of the results.
       folderToZip(singleStationState$outputFolders()$outputdir)
       pathToZipFile <- zipFiles(folderToZip(), excludePattern = "*.zip",
         destinationFolder = singleStationState$outputFolders()$baseFolder,
         destinationFileName = paste0(singleStationState$stationName(), ".zip"))
       indicesZipLink(getLinkFromPath(pathToZipFile, "here"))
   
       enable("calculateIndices")
       # singleStationState$indexCalculationErrors("")
       singleStationState$indexCalculationStatus("Done")
       on.exit(progress$close())       # place on.exit here so that errors that aren't manually caught by QC (like base periods larger than the data) are left on-screen for users to see.
    },
    error = function(cond) {
          progress$set(message=cond$message, value=0, detail = paste("ERROR: ",cond$message))
          print(paste("Error:", cond$message))
          return(paste("Error:", cond$message))
    })
    return(out)
  })

  # output$indicesLinkTop <- renderText(getLinkTextTopMiddle())
  output$indicesLinkMiddle <- renderText(getLinkTextTopMiddle())
  output$indicesLink <- renderText(getLinkText())

  getLinkTextTopMiddle <- function() {
    if (singleStationState$indexCalculationStatus() == "Done") {
      if (isLocal) {
        HTML("<h5>Please view the output in the following directory: <b>", folderToZip(), "</b></h5>")
      } else {
        HTML("<h5>Calculated Indices available ", indicesZipLink(), "</h5>")
      }
    } else {
      ""
    }
  }

  getLinkText <- function() {
    if (singleStationState$indexCalculationStatus() == "Done") {
      if (isLocal) {
        HTML("<b>Calculated Indices</b><br /><p>Please view the output in the following directory: <b>", folderToZip(), "</b></p>")
      } else {
        HTML("<b>Calculated Indices</b><br /><p>Calculated Indices available ", indicesZipLink(), "</p>")
      }
    } else {
      ""
    }
  }

  observeEvent(singleStationState$indexCalculationStatus(), {
    if (singleStationState$indexCalculationStatus() == "Done") {
      session$sendCustomMessage("enableTab", "process_single_station_step_4")
    }
  })

  observeEvent(input$btn_next_step_3, {
    tabName <- "process_single_station_step_4"
    session$sendCustomMessage("enableTab", tabName)
    updateTabsetPanel(parentSession, "process_single_station", selected = tabName)
  })

  outputOptions(output, "slickRIndices", suspendWhenHidden = TRUE) # otherwise renders incorrectly initially

  observe(toggleState("btn_next_step_3", singleStationState$indexCalculationStatus() == "Done"))

  return(list(singleStationState = singleStationState))
}
