#' scDD
#' 
#' Find genes with differential distributions (DD) across two conditions
#' 
#' @details Find genes with differential distributions (DD) across two 
#' conditions.  Models each log-transformed gene as a Dirichlet 
#'   Process Mixture of normals and uses a permutation test to determine 
#'   whether condition membership is independent of sample clustering.
#'   The FDR adjusted (Benjamini-Hochberg) permutation p-value is returned 
#'   along with the classification of each significant gene 
#'   (with p-value less than 0.05 (or 0.025 if also testing for a difference
#'    in the proportion of zeroes)) into one of four categories 
#'   (DE, DP, DM, DB).  For genes that do not show significant influence, 
#'   of condition on clustering, an optional test of whether the 
#'   proportion of zeroes (dropout rate) is different across conditions is 
#'   performed (DZ).
#'   
#' @param SCdat An object of class \code{SingleCellExperiment} that contains 
#' normalized single-cell expression and metadata. The \code{assays} 
#'   slot contains a named list of matrices, where the normalized counts are 
#'   housed in the one named \code{normcounts}.  This matrix should have one
#'    row for each gene and one sample for each column.  
#'   The \code{colData} slot should contain a data.frame with one row per 
#'   sample and columns that contain metadata for each sample.  This data.frame
#'   should contain a variable that represents biological condition, which is 
#'   in the form of numeric values (either 1 or 2) that indicates which 
#'   condition each sample belongs to (in the same order as the columns of 
#'   \code{normcounts}).  Optional additional metadata about each cell can also
#'   be contained in this data.frame, and additional information about the 
#'   experiment can be contained in the \code{metadata} slot as a list.
#' 
#' @param prior_param A list of prior parameter values to be used when modeling
#'  each gene as a mixture of DP normals.  Default 
#'    values are given that specify a vague prior distribution on the 
#'    cluster-specific means and variances.
#'    
#' @param permutations The number of permutations to be used in calculating 
#' empirical p-values.  If set to zero (default),
#'   the full Bayes Factor permutation test will not be performed.  Instead, 
#'   a fast procedure to identify the genes with significantly different
#'   expression distributions will be performed using the nonparametric 
#'   Kolmogorov-Smirnov test, which tests the null hypothesis that 
#'   the samples are generated from the same continuous distribution.  
#'   This test will yield
#'   slightly lower power than the full permutation testing framework 
#'   (this effect is more pronounced at smaller sample 
#'   sizes, and is more pronounced in the DB category), but is orders of 
#'   magnitude faster.  This option
#'   is recommended when compute resources are limited.  The remaining 
#'   steps of the scDD framework will remain unchanged
#'   (namely, categorizing the significant DD genes into patterns that 
#'   represent the major distributional changes, 
#'   as well as the ability to visualize the results with violin plots 
#'   using the \code{sideViolin} function).
#' 
#' @param testZeroes Logical indicating whether or not to test for a 
#' difference in the proportion of zeroes. This will only be done for genes 
#' that have at least one zero value (genes where all cells have a nonzero value
#' will have a `zero.pvalue` of NA).
#' 
#' @param level numeric value between 0 and 1 that specifies the alpha level
#' for significance of a differential gene test (default value 0.05). This is 
#' used to decide whether to classify a gene into one of the differential
#' patterns. If `testZeroes` is FALSE and the adjusted p-value for a given gene 
#' is below `level`, then the gene is categorized. Alternatively, if `testZeroes` 
#' is TRUE, then the adjusted p-value must be below `level/2` in order to be
#' considered significant and categorized. This is done to control for multiple
#' testing since `testZeroes=TRUE` means that each gene is tested for a 
#' difference in nonzeroes and zeroes separately.
#' 
#' @param adjust.perms Logical indicating whether or not to adjust the 
#' permutation tests for the sample
#'   detection rate (proportion of nonzero values).  If true, the 
#'   residuals of a linear model adjusted for 
#'   detection rate are permuted, and new fitted values are 
#'   obtained using these residuals.
#'  
#' @param param a \code{MulticoreParam} or \code{SnowParam} object of 
#' the \code{BiocParallel}
#' package that defines a parallel backend.  The default option is 
#' \code{BiocParallel::bpparam()} which will automatically creates a cluster 
#' appropriate for 
#' the operating system.  Alternatively, the user can specify the number
#' of cores they wish to use by first creating the corresponding 
#' \code{MulticoreParam} (for Linux-like OS) or \code{SnowParam} (for Windows)
#' object, and then passing it into the \code{scDD}
#' function. This could be done to specify a parallel backend on a Linux-like
#' OS with, say 12 
#' cores by setting \code{param=BiocParallel::MulticoreParam(workers=12)}
#'  
#' @param parallelBy For the permutation test (if invoked), the manner in 
#' which to parallelize.  The default option
#'  is \code{"Genes"} which will spawn processes that divide up the genes 
#'  across all cores defined in \code{param} cores, and then loop through the 
#'  permutations. 
#'  The alternate option is \code{"Permutations"} which
#'  loop through each gene and spawn processes that divide up the permutations 
#'  across all cores defined in \code{param}.  
#'  The default option is recommended when analyzing more genes than the number
#'   of permutations.
#' 
#' @param condition A character object that contains the name of the column in 
#' \code{colData} that represents 
#'  the biological group or condition of interest (e.g. treatment versus 
#'  control).  Note that this variable should only contain two 
#'  possible values since \code{scDD} can currently only handle two-group 
#'  comparisons.  The default option assumes that there
#'  is a column named "condition" that contains this variable. 
#'  
#' @param min.size a positive integer that specifies the minimum size of a 
#' cluster (number of cells) for it to be used
#'  during the classification step.  Any clusters containing fewer than 
#'  \code{min.size} cells will be considered an outlier
#'  cluster and ignored in the classfication algorithm.  The default value
#'   is three.
#'   
#' @param min.nonzero a positive integer that specifies the minimum number of
#' nonzero cells in each condition required for the test of differential 
#' distributions.  If a gene has fewer nonzero cells per condition, it will
#' still be tested for DZ (if \code{testZeroes} is TRUE). Default value is
#' NULL (no minimum value is enforced).
#' 
#' @param categorize a logical indicating whether to determine which 
#' categories (DE, DP, DM, DB) each gene belongs to (default = TRUE). This
#' can only be set to FALSE if `permutations` is set to zero, since the full
#' model fitting will automatically be carried out if permutations are run.
#' 
#' @return A \code{SingleCellExperiment} object that contains the data and 
#' sample information from the input object, but where the results objects
#' are now added to the \code{metadata} slot. The metadata slot is now a
#' list with four items: the first (main results object) is a data.frame 
#' with the following columns: 
#' \itemize{
#'   \item `gene`: gene name (matches rownames of SCdat)
#'   \item `DDcategory`: name of the DD (DE, DP, DM, DB, DZ) pattern (or NS = not significant) 
#'   \item `Clusters.combined`: the number of clusters identified overall
#'   \item `Clusters.C1`: the number of clusters identified in condition 1 alone
#'   \item `Clusters.C2`: the number of clusters identified in condition 2 alone
#'   \item `nonzero.pvalue`: permutation (or KS) p-value for testing difference
#'   in nonzero expression values
#'   \item `nonzero.pvalue.adj`: Benjamini-Hochberg adjusted version of the 
#'     `nonzero.pvalue`column
#'   \item `zero.pvalue`: p-value for test of difference in dropout rate 
#'   (only if `testZeroes` is TRUE) 
#'   \item `zero.pvalue`: Benjamini-Hochberg adjusted version of the previous column 
#'   (only if `testZeroes` is TRUE) 
#'   \item `combined.pvalue`: Fisher's combined p-value for a difference in nonzero or zero values
#'   (only if `testZeroes` is TRUE). 
#'   \item `combined.pvalue.adj`: Benjamini-Hochberg adjusted version of the previous column 
#'   (only if `testZeroes` is TRUE) 
#' }
#'  
#' The remaining three elements are matrices (first for condition
#'   1 and 2 combined, 
#'  then condition 1 alone, then condition 2 alone) that contains the cluster
#'   memberships for each sample (cluster 1,2,3,...) in columns and
#'  genes in rows.  Zeroes, which are not involved in the clustering, are
#'   labeled as zero.  See the \code{results} function for a convenient
#'   way to extract these results objects.
#'  
#' @export
#'
#' @importFrom BiocParallel bplapply  
#' 
#' @importFrom BiocParallel register
#' 
#' @importFrom BiocParallel MulticoreParam
#' 
#' @importFrom BiocParallel bpparam
#' 
#' @importFrom parallel detectCores
#' 
#' @importFrom S4Vectors metadata
#' 
#' @import SingleCellExperiment
#' 
#' @import SummarizedExperiment
#' 
#' @references Korthauer KD, Chu LF, Newton MA, Li Y, Thomson J, Stewart R, 
#' Kendziorski C. A statistical approach for identifying differential 
#' distributions
#' in single-cell RNA-seq experiments. Genome Biology. 2016 Oct 25;17(1):222. 
#' \url{https://genomebiology.biomedcentral.com/articles/10.1186/s13059-016-
#' 1077-y}
#'  
#' @examples 
#'  
#' # load toy simulated example SingleCellExperiment object to find DD genes
#' 
#' data(scDatExSim)
#' 
#' 
#' # check that this object is a member of the SingleCellExperiment class
#' # and that it contains 200 samples and 30 genes
#' 
#' class(scDatExSim)
#' show(scDatExSim)
#' 
#' 
#' # set arguments to pass to scDD function
#' # we will perform 100 permutations on each of the 30 genes
#' 
#' prior_param=list(alpha=0.01, mu0=0, s0=0.01, a0=0.01, b0=0.01)
#' nperms <- 100
#' 
#' 
#' # call the scDD function to perform permutations, classify DD genes, 
#' # and return results
#' # we won't perform the test for a difference in the proportion of zeroes  
#' # since none exists in this simulated toy example data
#' # this step will take significantly longer with more genes and/or 
#' # more permutations
#' 
#' scDatExSim <- scDD(scDatExSim, prior_param=prior_param, permutations=nperms, 
#'             testZeroes=FALSE)

scDD <- function(SCdat, 
                 prior_param=list(alpha=0.10, mu0=0, s0=0.01, a0=0.01, b0=0.01),
                 permutations=0,
                 testZeroes=TRUE, adjust.perms=FALSE, 
                 param=bpparam(), 
                 parallelBy=c("Genes", "Permutations"),
                 condition="condition", min.size=3,
                 min.nonzero=NULL,
                 level=0.05, categorize = TRUE){
  
  # check whether SCdat is a member of the SingleCellExperiment class
  if(!("SingleCellExperiment" %in% class(SCdat))){
    stop("Please provide a valid 'SingleCellExperiment' object.")
  }
  
  if (is.null(assayNames(SCdat)) || !("normcounts" %in% assayNames(SCdat))) {
    stop("Please make sure the 'SingleCellExperiment' object includes ",
         "an assays slot named 'normcounts' that contains normalized ",
         "counts on the original scale")
  }
  
  if (!categorize && permutations != 0){
    stop("Categorization will be carried out if permuations are run.")
  }
  
  parallelBy <- match.arg(parallelBy)
  
  # unpack prior param objects
  alpha = prior_param$alpha
  m0 = prior_param$mu0
  s0 = prior_param$s0
  a0 = prior_param$a0
  b0 = prior_param$b0
  
  # check that condition inputs are valid
  if (length(unique(colData(SCdat)[[condition]])) != 2 | 
      length(colData(SCdat)[[condition]]) != ncol(normcounts(SCdat))){
    stop("Error: Please specify valid condition labels.")
  }
  
  # reference category/condition - the first listed one
  ref <- unique(colData(SCdat)[[condition]])[1]
  
  # check for genes with negative expression values
  if (sum(normcounts(SCdat) < 0) > 0){
    stop(paste0("Error: Negative values for Normalized Expression counts ",
                "detected. Please ensure all counts are non-negative"))
  }
  
  # check for genes that are all (or almost all) zeroes
  if (is.null(min.nonzero)){
    min.nonzero <- min.size
  }
  tofit <- which(
           (rowSums(normcounts(SCdat)[,colData(SCdat)[[condition]]==ref,drop=FALSE]>0) >= 
             max(min.size,2,min.nonzero)) &
           (rowSums(normcounts(SCdat)[,colData(SCdat)[[condition]]!=ref,drop=FALSE]>0) >= 
              max(min.size,2,min.nonzero)))
  
  if (length(tofit) < nrow(normcounts(SCdat))){
    if(testZeroes){
      message(paste0("Notice: ", nrow(normcounts(SCdat))-length(tofit), 
              " genes have less than ", min.nonzero, 
              " nonzero cells per condition. ",
              " Only testing for DZ for these genes."))  
    }else{
      message(paste0("Notice: ", nrow(normcounts(SCdat))-length(tofit), 
                     " genes have less than ", min.nonzero, 
                     " nonzero cells per condition. ",
                     " Skipping these genes."))  
    }
  }
  
  # check for genes for which all nonzero values are identical within at least 
  # one of the conditions. These will cause problems in model fitting
  skipConstant <- which( 
                apply(normcounts(SCdat)[tofit,
                                       colData(SCdat)[[condition]]==ref, drop=FALSE], 1,
                                function(x) length(unique(x[x>0])) == 1) |
                apply(normcounts(SCdat)[tofit,
                                       colData(SCdat)[[condition]]!=ref, drop=FALSE], 1,
                                function(x) length(unique(x[x>0])) == 1) )
  if (length(skipConstant) > 0){
    if(testZeroes){
      message(paste0("Notice: ", length(skipConstant), 
                     " Genes have constant nonzero values. ", 
                     " Only testing for DZ for these genes."))  
    }else{
      message(paste0("Notice: ", length(skipConstant), 
                     " Genes have constant nonzero values. ", 
                     " Skipping these genes."))  
    }
    tofit <- tofit[-skipConstant]
  }
  
  message(paste0("Setting up parallel back-end using ", 
                 param$workers, " cores" ))
  BiocParallel::register(BPPARAM = param)
  
  oa <- c1 <- c2 <- vector("list", nrow(normcounts(SCdat)[tofit,,drop=FALSE]))
  bf <- den <- comps.all <- 
    comps.c1 <- comps.c2 <- rep(NA, nrow(normcounts(SCdat)[tofit,,drop=FALSE]))
  
  # cluster each gene in SCdat
  if (categorize)
    message("Clustering observed expression data for each gene")
  
  if (permutations == 0){

    # function to fit one gene 
    genefit <- function(y){
      cond0 <- colData(SCdat)[[condition]][y>0]
      y <- log(y[y>0])
      
      oa <- mclustRestricted(y, restrict=TRUE, min.size=min.size)
      c1 <- mclustRestricted(y[cond0==ref], restrict=TRUE, min.size=min.size)
      c2 <- mclustRestricted(y[cond0!=ref], restrict=TRUE, min.size=min.size)
    
      return(list(
        oa=oa,
        c1=c1,
        c2=c2
      ))
    }
    
    if (categorize){
      out <- bplapply(1:nrow(normcounts(SCdat)[tofit,,drop=FALSE]), function(x) 
        genefit(normcounts(SCdat)[tofit[x],]))
      oa <- lapply(out, function(x) x[["oa"]])
      c1 <- lapply(out, function(x) x[["c1"]])
      c2 <- lapply(out, function(x) x[["c2"]])
      rm(out); gc()
    
      comps.all <- unlist(lapply(oa, function(x) luOutlier(x$class, min.size)))
      comps.c1  <- unlist(lapply(c1, function(x) luOutlier(x$class, min.size)))
      comps.c2  <- unlist(lapply(c2, function(x) luOutlier(x$class, min.size)))
    }
    
    message("Notice: Number of permutations is set to zero; using 
            Kolmogorov-Smirnov to test for differences in distributions
            instead of the Bayes Factor permutation test")
    
    res_ks <- testKS(normcounts(SCdat)[tofit,,drop=FALSE], 
                     colData(SCdat)[[condition]], inclZero=FALSE)
    
    if (testZeroes){
      sig <- which(res_ks$p < level/2)
    }else{
      sig <- which(res_ks$p < level)
    }
    
    pvals <- res_ks$p.unadj
    
  }else{ 

    # function to fit one gene 
    genefit <- function(y){
      cond0 <- colData(SCdat)[[condition]][y>0]
      y <- log(y[y>0])
      
      oa <- mclustRestricted(y, restrict=TRUE, min.size=min.size)
      c1 <- mclustRestricted(y[cond0==ref], restrict=TRUE, min.size=min.size)
      c2 <- mclustRestricted(y[cond0!=ref], restrict=TRUE, min.size=min.size)
      
      bf <- jointPosterior(y[cond0==ref], c1, alpha, m0, s0, a0, b0) + 
        jointPosterior(y[cond0!=ref], c2, alpha, m0, s0, a0, b0) 
      den <- jointPosterior(y, oa, alpha, m0, s0, a0, b0)
      return(list(
        oa=oa,
        c1=c1,
        c2=c2,
        bf=bf,
        den=den
      ))
    }
    
    out <- bplapply(1:nrow(normcounts(SCdat)[tofit,,drop=FALSE]), function(x) 
      genefit(normcounts(SCdat)[tofit[x],]))
    oa <- lapply(out, function(x) x[["oa"]])
    c1 <- lapply(out, function(x) x[["c1"]])
    c2 <- lapply(out, function(x) x[["c2"]])
    bf <- unlist(lapply(out, function(x) x[["bf"]]))
    den<- unlist(lapply(out, function(x) x[["den"]]))
    rm(out); gc()
    
    comps.all <- unlist(lapply(oa, function(x) luOutlier(x$class, min.size)))
    comps.c1  <- unlist(lapply(c1, function(x) luOutlier(x$class, min.size)))
    comps.c2  <- unlist(lapply(c2, function(x) luOutlier(x$class, min.size)))
  

      # obtain Bayes Factor score numerators for each permutation
      message("Performing permutations to evaluate independence of clustering
              and condition for each gene")
      message(paste0("Parallelizing by ", parallelBy))
      bf.perm <- vector("list", nrow(normcounts(SCdat)[tofit,,drop=FALSE]))
      names(bf.perm) <- rownames(normcounts(SCdat)[tofit,,drop=FALSE])
      
      if(parallelBy=="Permutations"){
        if(adjust.perms){
          C <- apply(normcounts(SCdat)[tofit,,drop=FALSE], 2, 
                     function(x) sum(x>0)/length(x))
          
          t1 <- proc.time()
          for (g in 1:nrow(normcounts(SCdat)[tofit,,drop=FALSE])){
            bf.perm[[g]] <- permMclustCov(normcounts(SCdat)[tofit[g],], 
                                          permutations, C, 
                                          colData(SCdat)[[condition]], 
                                          remove.zeroes=TRUE, 
                                          log.transf=TRUE, restrict=TRUE,
                                          min.size=min.size,
                                          alpha, m0, s0, a0, b0, ref)
            
            if (g%%1000 == 0){
              t2 <- proc.time()
              message(paste0(g, " genes completed at ", date(), ", took ", 
                             round((t2-t1)[3]/60, 2), " minutes")) 
              t1 <- t2
            }
          }
          
        }else{
          t1 <- proc.time()
          for (g in 1:nrow(normcounts(SCdat)[tofit,,drop=FALSE])){
            bf.perm[[g]] <- permMclust(normcounts(SCdat[tofit[g],]), 
                                       permutations,
                                       colData(SCdat)[[condition]], 
                                       remove.zeroes=TRUE, log.transf=TRUE, 
                                       restrict=TRUE,
                                       min.size=min.size, 
                                       alpha, m0, s0, a0, b0, ref)
            
            if (g%%1000 == 0){
              t2 <- proc.time()
              message(paste0(g, " genes completed at ", date(), ", took ", 
                             round((t2-t1)[3]/60, 2), " minutes")) 
              t1 <- t2
            }
          }
      }
      }else if(parallelBy=="Genes"){
        C <- apply(normcounts(SCdat)[tofit,,drop=FALSE], 2, function(x) sum(x>0)/length(x))
        bf.perm <- bplapply(1:nrow(normcounts(SCdat)[tofit,,drop=FALSE]), function(x) 
              permMclustGene(normcounts(SCdat)[tofit[x],], adjust.perms, 
                             permutations, colData(SCdat)[[condition]], 
                             remove.zeroes=TRUE, log.transf=TRUE, restrict=TRUE,
                             min.size=min.size,
                             alpha, m0, s0, a0, b0, C, ref))
      }else{stop("Please specify either 'Permutations' or 'Genes' to 
                 parallelize by using the parallelizeBy argument")}
      
      if (adjust.perms){
        pvals <- sapply(1:nrow(normcounts(SCdat)[tofit,,drop=FALSE]), function(x) 
          sum( bf.perm[[x]] > bf[x] - den[x] ) )/(permutations)
      }else{
        pvals <- sapply(1:nrow(normcounts(SCdat)[tofit,,drop=FALSE]), function(x) 
          sum( bf.perm[[x]] > bf[x]) ) / (permutations)
      }
      
      if (testZeroes){
        sig <- which(p.adjust(pvals, method="BH") < level/2)
      }else{
        sig <- which(p.adjust(pvals, method="BH") < level)
      }
  }
  
  cats.all <- pvals.all <- rep(NA, nrow(normcounts(SCdat)))
  pvals.all[tofit] <- pvals
  
  if (categorize){
    message("Classifying significant genes into patterns")
    dd.cats <- classifyDD(normcounts(SCdat)[tofit,,drop=FALSE], colData(SCdat)[[condition]],
                        sig, oa, c1, c2, alpha=alpha, 
                        m0=m0, s0=s0, a0=a0, b0=b0, 
                        log.nonzero=TRUE, ref=ref, min.size=min.size)
  
    cats <- rep("NS", nrow(normcounts(SCdat)[tofit,,drop=FALSE]))
    cats[sig] <- dd.cats
  
    extraDP <- feDP(normcounts(SCdat)[tofit,,drop=FALSE], colData(SCdat)[[condition]], 
                  sig, oa, c1, c2, log.nonzero=TRUE,
                  testZeroes=testZeroes, adjust.perms=adjust.perms, 
                  min.size=min.size)
    cats[-sig] <- names(extraDP)
  
    # classify additional genes with evidence of DD in 
    # the form of a mean shift found by 'extraDP'
    if(testZeroes){
      NCs <- which(p.adjust(pvals, method="BH") > level/2 & cats == "NC")
    }else{
      NCs <- which(p.adjust(pvals, method="BH") > level & cats == "NC")
    }
    NC.cats <- classifyDD(normcounts(SCdat)[tofit,,drop=FALSE], colData(SCdat)[[condition]],
                        NCs, oa, c1, c2, alpha=alpha, 
                        m0=m0, s0=s0, a0=a0, b0=b0, log.nonzero=TRUE, 
                        ref=ref, min.size=min.size)
    cats[NCs] <- NC.cats
    cats.all[tofit] <- cats
  }
  
  # zero test
  pvals.z <- rep(NA, nrow(normcounts(SCdat)))
  if (testZeroes){
    pvals.z <- testZeroes(normcounts(SCdat), colData(SCdat)[[condition]])
    cats.all[p.adjust(pvals.z, method="BH") < level/2 &
               !(cats.all %in% c("DE", "DP", "DM", "DB"))] <- "DZ"
    if (categorize)
      cats.all[p.adjust(pvals.z, method="BH") >= level/2 &
                 !(cats.all %in% c("DE", "DP", "DM", "DB"))] <- "NS"
  }
  
  # build MAP objects
  if (categorize){
    MAP1 <- matrix(1, nrow=nrow(normcounts(SCdat)), 
                 ncol=sum(colData(SCdat)[[condition]]==ref))
    MAP2 <- matrix(1, nrow=nrow(normcounts(SCdat)), 
                 ncol=sum(colData(SCdat)[[condition]]!=ref))
    MAP <- matrix(1, nrow=nrow(normcounts(SCdat)), 
                ncol=ncol(normcounts(SCdat)))
    rownames(MAP1) <- rownames(MAP2) <- rownames(MAP) <- rownames(SCdat)
    colnames(MAP1) <- colnames(SCdat[,colData(SCdat)[[condition]]==ref])
    colnames(MAP2) <- colnames(SCdat[,colData(SCdat)[[condition]]!=ref])
    colnames(MAP) <- colnames(SCdat)
    MAP1[normcounts(SCdat[, colData(SCdat)[[condition]]==ref])==0] <- 0
    MAP2[normcounts(SCdat[, colData(SCdat)[[condition]]!=ref])==0] <- 0
    MAP[normcounts(SCdat)==0] <- 0
  
    for (g in 1:nrow(normcounts(SCdat)[tofit,,drop=FALSE])){
      MAP1[tofit[g],][normcounts(SCdat[tofit[g], 
                  colData(SCdat)[[condition]]==ref])!=0] <- c1[[g]]$class 
      MAP2[tofit[g],][normcounts(SCdat[tofit[g], 
                  colData(SCdat)[[condition]]!=ref])!=0] <- c2[[g]]$class
      MAP[tofit[g],][normcounts(SCdat[tofit[g], ])!=0] <- oa[[g]]$class
    }
  }else{
    MAP1 <- MAP2 <- MAP <- "Categorize set to FALSE; no clustering provided."
  }
  
  comps.all.ALL <- comps.c1.ALL <- comps.c2.ALL <- rep(NA, 
                                                       nrow(normcounts(SCdat)))
  comps.all.ALL[tofit] <- comps.all
  comps.c1.ALL[tofit] <- comps.c1
  comps.c2.ALL[tofit] <- comps.c2
  
  Genes = data.frame(gene=rownames(SCdat), 
                   DDcategory=cats.all, 
                   Clusters.combined=comps.all.ALL, 
                   Clusters.c1=comps.c1.ALL, 
                   Clusters.c2=comps.c2.ALL,
                   nonzero.pvalue=pvals.all,
                   nonzero.pvalue.adj=p.adjust(pvals.all, method="BH"))
  
  # only give dropout-related p-values if testZeroes = TRUE 
  if(testZeroes){
    fishersCombinedPval = function(x){ 
      if(sum(is.na(x)) == 0){
        pchisq(-2 * sum(log(x)), df=2*length(x),lower=FALSE)
      }else if(sum(is.na(x)) == 1){
        x[!is.na(x)]
      }else{
        NA
      }
    }
    
    # compute combined p-value
    pvals.comb <- apply(cbind(pvals.all, pvals.z), 1, function(x)
      fishersCombinedPval(x))
    
    Genes <- cbind(Genes,
                   zero.pvalue=pvals.z, 
                   zero.pvalue.adj=p.adjust(pvals.z, method="BH"),
                   combined.pvalue=pvals.comb,
                   combined.pvalue.adj=p.adjust(pvals.comb, method="BH"))
  }
  
  rownames(Genes) <- rownames(SCdat)
  
  # place these results objects in the appropriately named assays()
  # slots of the SingleCellExperiment object
  metadata(SCdat)[["Genes"]] <- Genes
  metadata(SCdat)[["Zhat.combined"]] <- MAP
  metadata(SCdat)[["Zhat.c1"]] <- MAP1
  metadata(SCdat)[["Zhat.c2"]] <- MAP2
  
  # return...
  return(SCdat)
}


