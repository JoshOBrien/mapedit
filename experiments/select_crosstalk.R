library(sf)
library(leaflet)
library(plotly)
library(crosstalk)
library(htmltools)

boroughs<- st_read("http://services5.arcgis.com/GfwWNkhOj9bNBqoJ/arcgis/rest/services/nybb/FeatureServer/0/query?where=1=1&outFields=*&outSR=4326&f=geojson")
boroughs$x <- seq(1:5)
boroughs$y <- seq(2,10,2)

boroughs_sd <- SharedData$new(
  boroughs,
  key=~BoroCode,
  # provide explicit group so we can easily refer to this later
  group = "boroughs"
)

map <- leaflet(boroughs_sd) %>%
  addProviderTiles(providers$CartoDB.Positron) %>%
  addPolygons(
    data=boroughs,
    layerId = ~BoroCode,
    color = "#444444",
    weight = 1,
    smoothFactor = 0.5,
    opacity = 1.0,
    fillOpacity = 0.5,
    fillColor = ~colorQuantile("Greens", x)(x)#,
#  turn off highlight since it interferes with selection styling
#   if careful with styling could have both highlight and select
#    highlightOptions = highlightOptions(color = "white", weight = 2)
  )

# borrow from https://github.com/r-spatial/mapedit/blob/master/R/query.R#L73-L132
#   to select/deselect features but instead of Shiny.onInputChange
#   use crosstalk to manage state
add_select_script <- function(lf, styleFalse, styleTrue, ns="") {
  ## check for existing onRender jsHook?

  htmlwidgets::onRender(
    lf,
    sprintf(
"
function(el,x) {
  var lf = this;
  var style_obj = {
    'false': %s,
    'true': %s
  }

  var crosstalk_group = '%s';

  // instead of shiny input as our state manager
  //   use crosstalk
  if(typeof(crosstalk) !== 'undefined' && crosstalk_group) {
    var ct_sel = new crosstalk.SelectionHandle()
    ct_sel.setGroup(crosstalk_group)
    ct_sel.on('change', function(x){
      if(x.sender !== ct_sel) { //ignore select from this map
        lf.eachLayer(function(lyr){
          if(lyr.options && lyr.options.layerId) {
            var id = String(lyr.options.layerId)
            if(
              !x.value  ||
              (
                Array.isArray(x.value) &&
                x.value.filter(function(d) {
                  return d == id
                }).length === 0
              )
            ) {
              toggle_state(lyr, false)
              toggle_style(lyr, style_obj.false)
            }
            if(
              Array.isArray(x.value) &&
              x.value.filter(function(d) {
                return d == id
              }).length > 0
            ) {
              toggle_state(lyr, true)
              toggle_style(lyr, style_obj.true)
            }
          }
        })
      }
    })
  }

  // define our functions for toggling
  function toggle_style(layer, style_obj) {
    layer.setStyle(style_obj);
  };
  function toggle_state(layer, selected, init) {
    if(typeof(selected) !== 'undefined') {
      layer._mapedit_selected = selected;
    } else {
      selected = !layer._mapedit_selected;
      layer._mapedit_selected = selected;
    }
    if(typeof(Shiny) !== 'undefined' && Shiny.onInputChange && !init) {
      Shiny.onInputChange(
        '%s-mapedit_selected',
        {
          'group': layer.options.group,
          'id': layer.options.layerId,
          'selected': selected
        }
      )
    }

    return selected;
  };
  // set up click handler on each layer with a group name
  lf.eachLayer(function(lyr){
    if(lyr.on && lyr.options && lyr.options.layerId) {
      // start with all unselected ?
      toggle_state(lyr, false, init=true);
      toggle_style(lyr, style_obj[lyr._mapedit_selected]);
      lyr.on('click',function(e){
        var selected = toggle_state(e.target);
        toggle_style(e.target, style_obj[String(selected)]);

        if(ct_sel) {
          var ct_values = ct_sel.value;
          var id = lyr.options.layerId;
          if(selected) {
            if(!ct_values) {
              ct_sel.set([id, String(id)]) // do both since Plotly uses String id
            }
            // use filter instead of indexOf to allow inexact equality
            if(
              Array.isArray(ct_values) &&
              ct_values.filter(function(d) {
                return d == id
              }).length === 0
            ) {
              ct_sel.set(ct_values.concat([id, String(id)]))  // do both since Plotly uses String id
            }
          }

          if(ct_values && !selected) {
            ct_values.length > 1 ?
              ct_sel.set(
                ct_values.filter(function(d) {
                  return d != id
                })
              ) :
              ct_sel.set(null) // select all if nothing selected
          }
        }
      });
    }
  });
}
",
      jsonlite::toJSON(styleFalse, auto_unbox=TRUE),
      jsonlite::toJSON(styleTrue, auto_unbox=TRUE),
      if(inherits(getMapData(map), "SharedData")) {getMapData(map)$groupName()} else {""},
      ns
    )
  )
}


browsable(
  tagList(
    tags$div(
      style = "float:left; width: 49%;",
      add_select_script(
        map,
        styleFalse = list(fillOpacity = 0.2, weight = 1, opacity = 0.4, color="black"),
        styleTrue = list(fillOpacity = 0.7, weight = 3, opacity = 0.7, color="blue"),
        ns = ""
      )
    ),
    tags$div(
      style = "float:left; width: 49%;",
      plot_ly(boroughs_sd, x = ~x, y = ~y) %>%
        add_markers(alpha = 0.5,text = ~paste('Borough: ', BoroName)) %>%
        highlight(on = "plotly_selected")
    )
  )
)


# try it with DT datatable
library(DT)

# no reason to carry the load of the feature column
#   in the datatables
#   so we will modify the data to subtract the feature column
#   not necessary to use dplyr but select makes our life easy
#   also need to modify targets, colnames, and container
dt <- datatable(boroughs_sd, width="100%")
dt$x$data <- dplyr::select(dt$x$data, -geometry)
dt$x$options$columnDefs[[1]]$targets <- seq_len(ncol(boroughs)-1)
attr(dt$x, "colnames") <- attr(dt$x, "colnames")[which(attr(dt$x, "colnames") != "geometry")]
dt$x$container <- gsub(x=dt$x$container, pattern="<th>geometry</th>\n", replacement="")
dt


browsable(
  tagList(
    tags$div(
      style = "float:left; width: 49%;",
      add_select_script(
        map,
        styleFalse = list(fillOpacity = 0.2, weight = 1, opacity = 0.4, color="black"),
        styleTrue = list(fillOpacity = 0.7, weight = 3, opacity = 0.7, color="blue"),
        ns = ""
      )
    ),
    tags$div(
      style = "float:left; width: 49%;",
      dt
    )
  )
)


# now try leaflet, plotly, and dt
#   this unfortunately does not work
#   exactly as we would like but plotly use of String key
#   seems to cause the problem
#   fixing Plotly is out of scope of this project
#   but I might take a look at some point to submit pull
browsable(
  tagList(
    tags$div(
      style = "float:left; width: 32%;",
      add_select_script(
        map,
        styleFalse = list(fillOpacity = 0.2, weight = 1, opacity = 0.4, color="black"),
        styleTrue = list(fillOpacity = 0.7, weight = 3, opacity = 0.7, color="blue"),
        ns = ""
      )
    ),
    tags$div(
      style = "float:left; width: 32%;",
      plot_ly(boroughs_sd, x = ~x, y = ~y) %>%
        add_markers(alpha = 0.5,text = ~paste('Borough: ', BoroName)) %>%
        highlight(on = "plotly_selected")
    ),
    tags$div(
      style = "float:left; width: 32%;",
      dt
    )
  )
)
