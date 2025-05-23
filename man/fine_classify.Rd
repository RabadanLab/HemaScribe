% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/HemaScribe.R
\name{fine_classify}
\alias{fine_classify}
\title{Fine classifier}
\usage{
fine_classify(input, reference = "WT", return.full = FALSE)
}
\arguments{
\item{input}{A SingleCellExperiment or Seurat object}

\item{reference}{Either "WT" or "5FU" (default: "WT")}

\item{return.full}{Whether to return full predictions directly (default: FALSE)}
}
\value{
An object of the same type as input with added annotations, or a dataframe with classifier results
}
\description{
This performs a fine-level annotation of HSPC cell types using single cell
RNA-sequencing references.  Two references are available: the default is to
use a wild-type hashing reference.
}
