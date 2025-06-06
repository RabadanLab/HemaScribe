#' Hematopoietic scores
#'
#' An optional prefiltering step to remove non-hematopoietic cells based on
#' scores from a hematopoietic gene list.
#'
#' @param input A SingleCellExperiment or Seurat object
#' @returns A dataframe of hematopoietic gene scores
#' @importFrom scater logNormCounts
#' @importFrom UCell ScoreSignatures_UCell
#' @importFrom SingleR SingleR
#' @export
hematopoietic_score <- function(input) {
  if (inherits(input, "SingleCellExperiment")) {
    sce <- input

    if (startsWith(rownames(sce)[1], "ENSMUSG")) {
      hem.sig <- list(hematopoietic.score = HemaScribeData$hematopoietic.genes$geneId)
    } else {
      hem.sig <- list(hematopoietic.score = HemaScribeData$hematopoietic.genes$geneSymbol)
    }

    sce <- UCell::ScoreSignatures_UCell(sce, features=hem.sig, name=NULL, ncores=4)

    hem.scores <- data.frame(t(SummarizedExperiment::assay(SingleCellExperiment::altExp(sce, "UCell"))))

  } else if (inherits(input, "Seurat")) {
    seurat <- input

    if (startsWith(rownames(seurat)[1], "ENSMUSG")) {
      hem.sig <- list(hematopoietic.score = HemaScribeData$hematopoietic.genes$geneId)
    } else {
      hem.sig <- list(hematopoietic.score = HemaScribeData$hematopoietic.genes$geneSymbol)
    }

    seurat <- UCell::AddModuleScore_UCell(seurat, features=hem.sig, name=NULL, ncores=4)

    hem.scores <- data.frame(seurat$hematopoietic.score)
    colnames(hem.scores) <- "hematopoietic.score"

  } else {
    stop("Only SingleCellExperiment and Seurat formats are supported.")
  }

  return(hem.scores)
}

#' Broad classifier
#'
#' This performs a broad-level annotation of bone marrow cell types using
#' bulk RNA-sequencing data curated from Haeomopedia and Immgen.
#'
#' @param input A SingleCellExperiment or Seurat object
#' @param return.full Whether to return full predictions directly (default: FALSE)
#' @returns An object of the same type as input with added annotations, or a dataframe with classifier results
#' @export
broad_classify <- function(input, return.full = FALSE) {
  if (inherits(input, "SingleCellExperiment")) {
    sce <- input
  } else if (inherits(input, "Seurat")) {
    withCallingHandlers({
      sce <- Seurat::as.SingleCellExperiment(input)
    }, warning = function(w) {
      if (grepl("scale.data", conditionMessage(w))) {
        invokeRestart("muffleWarning")
      }
    })
  } else {
    stop("Only SingleCellExperiment and Seurat formats are supported.")
  }

  if (!("logcounts" %in% names(SummarizedExperiment::assays(sce)))) {
    sce <- scater::logNormCounts(sce)
  }

  if (startsWith(rownames(sce)[1], "ENSMUSG")) {
    ref <- HemaScribeData$ref.bulk$refs.geneIds
  } else {
    ref <- HemaScribeData$ref.bulk$refs.geneSymbols
  }
  labels <- HemaScribeData$ref.bulk$labels

  pred <- SingleR::SingleR(test = sce, ref = ref, labels = labels)
  pred$labels[pred$labels == "GMP"] <- "mGMP"
  pred$pruned.labels[pred$pruned.labels == "GMP"] <- "mGMP"

  if (return.full) {
    return(pred)
  }

  if (inherits(input, "SingleCellExperiment")) {
    sce$broad.annot <- pred$pruned.labels
    return(sce)
  } else if (inherits(input, "Seurat")) {
    seurat <- Seurat::AddMetaData(input, metadata = pred$pruned.labels, col.name = "broad.annot")
    return(seurat)
  }
}

#' Fine classifier
#'
#' This performs a fine-level annotation of HSPC cell types using single cell
#' RNA-sequencing references.  Two references are available: the default is to
#' use a wild-type hashing reference.
#'
#' @param input A SingleCellExperiment or Seurat object
#' @param reference Either "WT" or "5FU" (default: "WT")
#' @param return.full Whether to return full predictions directly (default: FALSE)
#' @returns An object of the same type as input with added annotations, or a dataframe with classifier results
#' @export
fine_classify <- function(input, reference = "WT", return.full = FALSE) {
  if (inherits(input, "Seurat")) {
    seurat <- input
  } else if (inherits(input, "SingleCellExperiment")) {
    seurat <- SeuratObject::as.Seurat(input)
  } else {
    stop("Only SingleCellExperiment and Seurat formats are supported.")
  }

  if (!("data" %in% SeuratObject::Layers(seurat))) {
    stop("Layer 'data' not available in Seurat object. Please normalize data first.")
  }

  if (!(reference %in% c("WT", "5FU"))) {
    stop("Reference must be one of 'WT' or '5FU'.")
  }
  if (reference == "WT") {
    ref <- HemaScribeData$ref.sc.wt
  } else if (reference == "5FU") {
    ref <- HemaScribeData$ref.sc.5fu
  }

  if (startsWith(rownames(seurat)[1], "ENSMUSG")) {
    rownames(ref@assays$integrated@data) <- translate(rownames(ref@assays$integrated@data))
    rownames(ref@assays$integrated@scale.data) <- translate(rownames(ref@assays$integrated@scale.data))
    ref@assays$integrated@var.features <- translate(ref@assays$integrated@var.features)
    rownames(ref@assays$integrated@meta.features) <- translate(rownames(ref@assays$integrated@meta.features))
    rownames(ref@reductions$pca@feature.loadings) <- translate(rownames(ref@reductions$pca@feature.loadings))
  }

  anchors <- Seurat::FindTransferAnchors(
    reference = ref,
    query = seurat,
    dims = 1:30,
    reference.reduction = "pca",
    verbose = FALSE
  )

  # Below, version where "pca" reduction not included in reference data.
  # withCallingHandlers({
  #   anchors <- Seurat::FindTransferAnchors(
  #     reference = ref,
  #     query = seurat,
  #     dims = 1:30,
  #     verbose = FALSE
  #   )}, warning = function(w) {
  #     if (grepl("scale.data", conditionMessage(w))) {
  #       invokeRestart("muffleWarning")
  #     }
  # })

  pred <- Seurat::TransferData(
    anchorset = anchors,
    refdata = ref$MULTI_ID,
    dims = 1:30,
    verbose = FALSE
  )
  pred$predicted.id[pred$predicted.id == "CFUE"] <- "EryP"

  if (return.full) {
    return(pred)
  }

  if (inherits(input, "Seurat")) {
    seurat <- Seurat::AddMetaData(seurat, metadata = pred$predicted.id, col.name = "fine.annot")
    return(seurat)
  } else if (inherits(input, "SingleCellExperiment")) {
    input$fine.annot <- pred$predicted.id
    return(input)
  }
}

#' Two-stage classifier
#'
#' This first performs the broad annotation of bone marrow cell types and then
#' applies the fine annotation to the cells that are annotated as HSPC.
#' Combined, HSPC-specific, and GMP-specific annotations are extracted from
#' these predictions.  An optional prefiltering step based on hematopoietic gene
#' scores is available; if no threshold is set, then the scores are merely
#' reported.
#'
#' @param input A SingleCellExperiment or Seurat object
#' @param prefilter Hematopoietic score threshold below which cells shall be excluded.  (default: 0)
#' @param reference Either "WT" or "5FU" (default: "WT")
#' @param return.full Whether to return full predictions directly (default: FALSE)
#' @returns An object of the same type as input with added annotations, or dataframes with classifier results.
#' @export
HemaScribe <- function(input, prefilter = 0, reference = "WT", return.full = FALSE) {
  rlang::inform("Calculating hematopoietic scores")
  hem.scores <- hematopoietic_score(input)

  rlang::inform("Classifying into broad cell types")
  input.hem <- input[,which(hem.scores$hematopoietic.score >= prefilter)]
  annotation.broad <- broad_classify(input.hem, return.full = TRUE)

  rlang::inform("Classifying into fine cell subtypes")
  input.hspc <- input.hem[,which(annotation.broad$pruned.labels == "HSPC")]
  skip.fine <- (ncol(input.hspc) < 30)
  if (!skip.fine) {
    annotation.fine <- fine_classify(input.hspc, reference = reference, return.full = TRUE)
  } else {
    rlang::warn("Not enough HSPCs.  Skipping fine annotation.")
  }

  rlang::inform("Returning final annotations")
  if (!skip.fine) {
    annotations.combined <- merge(annotation.broad["pruned.labels"], annotation.fine["predicted.id"], by=0, all.x=TRUE)

    rownames(annotations.combined) <- annotations.combined$Row.names
    annotations.combined$Row.names <- NULL
  } else {
    annotations.combined <- annotation.broad["pruned.labels"]
  }

  annotations.combined <- merge(hem.scores["hematopoietic.score"], annotations.combined, by=0, all.x=TRUE)
  rownames(annotations.combined) <- annotations.combined$Row.names
  annotations.combined$Row.names <- NULL

  if (!skip.fine) {
    colnames(annotations.combined) <- c("hematopoietic.score", "broad.annot", "fine.annot")
  } else {
    colnames(annotations.combined) <- c("hematopoietic.score", "broad.annot")
  }

  annotations.combined$broad.annot[is.na(annotations.combined$broad.annot)] <- "NotHem"

  if (!skip.fine) {
    annotations.combined$fine.annot[is.na(annotations.combined$fine.annot)] <- "NotHSPC"

    annotations.combined$combined.annot <- annotations.combined$fine.annot
    not.hspc <- (annotations.combined$fine.annot == "NotHSPC")
    annotations.combined$combined.annot[not.hspc] <- annotations.combined$broad.annot[not.hspc]
    annotations.combined$combined.annot[annotations.combined$combined.annot == "GMP"] <- "mGMP"

    annotations.combined$HSPC.annot <- annotations.combined$fine.annot
    combined.renaming <- list(CLP = "CLP", cMoP = "GMP", EryP = "EryP", mGMP = "GMP", GP = "GMP", Megakaryocyte = "MkP")
    for (nm in names(combined.renaming)) {
      annotations.combined$HSPC.annot[which(annotations.combined$broad.annot == nm)] <- combined.renaming[[nm]]
    }

    annotations.combined$GMP.annot <- "NotGMP"
    annotations.combined$GMP.annot[which(annotations.combined$broad.annot == "cMoP")] <- "cMoP"
    annotations.combined$GMP.annot[which(annotations.combined$broad.annot == "GMP")] <- "mGMP"
    annotations.combined$GMP.annot[which(annotations.combined$broad.annot == "GP")] <- "GP"
    annotations.combined$GMP.annot[which(annotations.combined$fine.annot == "GMP")] <- "mGMP"
  }

  if (return.full) {
    if (!skip.fine) {
      return(list(hem.scores = hem.scores, broad = annotation.broad, fine = annotation.fine, combined = annotations.combined))
    } else {
      return(list(hem.scores = hem.scores, broad = annotation.broad, fine = NA, combined = annotations.combined))
    }
  }

  if (inherits(input, "SingleCellExperiment")) {
    input$hem.score <- annotations.combined$hematopoietic.score
    input$broad.annot <- annotations.combined$broad.annot
    if (!skip.fine) {
      input$fine.annot <- annotations.combined$fine.annot
      input$combined.annot <- annotations.combined$combined.annot
      input$HSPC.annot <- annotations.combined$HSPC.annot
      input$GMP.annot <- annotations.combined$GMP.annot
    }
    return(input)
  } else if (inherits(input, "Seurat")) {
    seurat <- Seurat::AddMetaData(input, metadata = annotations.combined)
    return(seurat)
  }
}

#' Translate gene names to Ensembl IDs
#'
#' @param x List of gene names
#' @returns List of Ensembl IDs
translate <- function (x) {
  HemaScribeData$gene.dict[match(x, HemaScribeData$gene.dict$GeneSymbol), "GeneID"]
}
