#' Get data from Openaddresses
#'
#' @export
#'
#' @param x (character) URL for an openaddresses dataset, or an object of
#' class openadd
#' @param overwrite	(logical) Will only overwrite existing path
#' if \code{TRUE}
#' @param ... Pass on curl options to \code{\link[crul]{HttpClient}}
#'
#' @return a tibble (a data.frame), with attributes for original url and path
#' on disk
#' @references \url{https://openaddresses.io/}
#' @examples \dontrun{
#' (out1 <- oa_get("http://data.openaddresses.io/runs/142103/at/tirol.zip"))
#' (out2 <-
#'   oa_get("http://data.openaddresses.io/runs/142676/ca/bc/victoria.zip"))
#'
#' # from a openadd class object
#' oa_get(as_openadd(country="us", state="nv", city="las_vegas"))
#'
#' # combine data sets
#' (alldat <- oa_combine(out1, out2))
#'
#' # Map data
#' if (!requireNamespace("leaflet")) {
#'   install.packages("leaflet")
#' }
#' library(leaflet)
#' small <- out2[[1]][1:5000,]
#' leaflet(small) %>%
#'   addTiles() %>%
#'   addCircles(lat = ~LAT, lng = ~LON,
#'              popup = unname(apply(small[, c('NUMBER', 'STREET')], 1,
#'              paste, collapse = " ")))
#' }
oa_get <- function(x, overwrite = FALSE, ...) {
  UseMethod("oa_get")
}

#' @export
oa_get.default <- function(x, overwrite = FALSE, ...) {
  stop("no 'oa_get' method for class ", class(x), call. = FALSE)
}

#' @export
oa_get.openadd <- function(x, overwrite = FALSE, ...) {
  oa_get(x[[1]], ...)
}

#' @export
oa_get.character <- function(x, overwrite = FALSE, ...) {
  resp <- oa_GET(x, ...)
  structure(resp, class = "oa",
            id = x,
            path = make_path(x),
            readme = read_me(x),
            name = get_name(x))
}

oa_GET <- function(url, ...){
  if (is.null(url) || is.na(url)) stop("input was NULL or NA", call. = FALSE)
  if (!grepl("https?://|data\\.openaddresses\\.io", url)) {
    stop("input doesn't appear to be an Openaddresses URL", call. = FALSE)
  }
  make_basedir(oa_cache_path())
  file <- make_path(url)
  if ( file.exists(path.expand(file)) ) {
    ff <- file
    message("Reading from cached data")
  } else {
    cli <- crul::HttpClient$new(url = url, opts = list(...))
    temp <- cli$get(disk = file)
    temp$raise_for_status()
    ff <- temp$content
  }
  switch(strextract(basename(ff), "\\zip|csv|geojson"),
         csv = list(read_csv_(ff)),
         zip = read_zip_(ff),
         geojson = list(read_geojson_(ff))
  )
}

get_name <- function(x) gsub("\\..+", "", basename(x))

make_path <- function(x) {
  xx <- grep("[A-Za-z]", strsplit(x, "/")[[1]], value = TRUE)
  xx <- xx[!grepl("http|openaddresses|runs", xx)]
  file.path(oa_cache_path(), paste0(xx, collapse = "_"))
}

make_basedir <- function(path) dir.create(path, showWarnings = FALSE,
                                          recursive = TRUE)

read_csv_ <- function(x) suppressMessages(readr::read_csv(x))

read_zip_ <- function(fname) {
  exdir <- file.path(oa_cache_path(), strsplit(basename(fname), "\\.")[[1]][[1]])
  utils::unzip(fname, exdir = exdir)
  on.exit(unlink(fname))
  switch(
    file_type(exdir),
    csv = {
      files <- list.files(exdir, pattern = ".csv", full.names = TRUE,
                          recursive = TRUE)
      lapply(files, read_csv_)
    },
    shp = {
      files <- list.files(exdir, pattern = ".shp", full.names = TRUE,
                          recursive = TRUE)
      lapply(files, read_shp_)
    },
    geojson = {
      files <- list.files(exdir, pattern = ".geojson", full.names = TRUE,
                          recursive = TRUE)
      lapply(files, read_geojson_)
    }
  )
}

read_geojson_ <- function(x) {
  tibble::as_data_frame(jsonlite::fromJSON(x, flatten = TRUE)$features)
}

read_shp_ <- function(x) {
  tmp <- maptools::readShapeSpatial(x)
  tibble::as_data_frame(tmp@data)
}

read_me <- function(x) {
  dir <- sub("\\.zip|\\.csv|\\.geojson", "", make_path(x))
  ff <- list.files(dir, pattern = "README", ignore.case = TRUE,
                   full.names = TRUE)
  if (length(ff) == 0) {
    return(NULL)
  } else {
    return(paste0(readLines(ff), collapse = "\n"))
  }
}

file_type <- function(b) {
  ff <- basename(list.files(b, full.names = TRUE, recursive = TRUE))
  if (any(grepl("\\.csv", ff))) {
    "csv"
  } else if (any(grepl("\\.shp", ff))) {
    "shp"
  } else if (any(grepl("\\.geojson", ff))) {
    "geojson"
  } else {
    stop("no acceptable file types found: csv/geojson/shp", call. = FALSE)
  }
}

#' @export
print.oa <- function(x, ..., n = 10) {
  cat(paste0("<Openaddresses data> ", attr(x, "name")), sep = "\n")
  cat(sprintf("paths: %s", get_em(x)), sep = "\n")
  cat(paste0("data set sizes (NROW): ", paste0(vapply(x, NROW, 1),
                                               collapse = ", ")), sep = "\n")
  cat("first data_frame ...  ", sep = "\n")
  print(x[[1]], n = n)
}

get_em <- function(x) {
  paths <- attr(x, "path")
  minl <- min(c(3, length(paths)))
  tmp <- paste0(paths[1:minl], collapse = ", ")
  xx <- substring(tmp, 1, 40)
  if (nchar(tmp) > 40) paste0(xx, " ...") else xx
}
