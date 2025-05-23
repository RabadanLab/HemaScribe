% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/HemaScribe.R
\name{hematopoietic_score}
\alias{hematopoietic_score}
\title{Hematopoietic scores}
\usage{
hematopoietic_score(input)
}
\arguments{
\item{input}{A SingleCellExperiment or Seurat object}
}
\value{
A dataframe of hematopoietic gene scores
}
\description{
An optional prefiltering step to remove non-hematopoietic cells based on
scores from a hematopoietic gene list.
}
