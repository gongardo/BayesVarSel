#' @export
GibbsBvsF <-
  function(formula,
           data,
           prior.betas = "Robust",
           prior.models = "SBSB2",
           n.iter = 10000,
           init.model = "Full",
           n.burnin = 500,
           n.thin = 1,
           time.test = TRUE,
           priorprobs = NULL,
           seed = runif(1, 0, 16091956),
					 contrasts = "none") {


		# Factors: The null model only contains the intercept:	 			 
	  null.model = paste(as.formula(formula)[[2]], " ~ 1", sep="")
		cat("At this point, only the intercept is allowed in the simplest model\n")
		#contrasts is one of either "none" for our proposal and "given" using
		#the one in the factors (perhaps given by default by R)
		if (contrasts != "none" & contrasts != "given") stop("contrasts not defined.\n")
		#for prior.models="SBSB" use the hierarchical Scott-Berger over the dimension
		#for prior.models="SBSB2" use the hierarchical Scott-Berger over the rank
		
    formula <- as.formula(formula)
		
    null.model<- as.formula(null.model)

    #The response in the null model and in the full model must coincide
    if (formula[[2]] != null.model[[2]]){
      stop("The response in the full and null model does not coincide.\n")
    }

    #Let's define the result
    result <- list()

    #Get a tempdir as working directory
    wd <- tempdir()
    #remove all the previous documents in the working directory
    unlink(paste(wd, "*", sep = "/"))

    #evaluate the null model:
    lmnull <- lm(formula = null.model, data, y = TRUE, x = TRUE)
    fixed.cov <- dimnames(lmnull$x)[[2]]

    #Set the design matrix if fixed covariates present:
    if (!is.null(fixed.cov)) {
      #Eval the full model
      lmfull = lm(formula,
                  data = data,
                  y = TRUE,
                  x = TRUE)
			#Factors:
			#before:X.full <- lmfull$x
			if (contrasts == "none") {						
      	X.full<- lmerTest:::get_rdX(lmfull) #rank defficient paramet
			}
			if (contrasts == "given") {
				X.full <- lmfull$x
			}
      namesx <- dimnames(X.full)[[2]]
    
      #check if null model is contained in the full one:
      namesnull <- dimnames(lmnull$x)[[2]]
      "%notin%" <- function(x, table) match(x, table, nomatch = 0) == 0
      for (i in 1:length(namesnull)){
        if (namesnull[i] %notin% namesx) {
          cat("Error in var: ", namesnull[i], "\n")
          stop("null model is not nested in full model\n")
        }
      }
			
      #Is there any variable to select from?
      if (length(namesx) == length(namesnull)) {
        stop(
          "The number of fixed covariates is equal to the number of covariates in the full model. No model selection can be done\n"
        )
      }


      #position for fixed variables in the full model
      fixed.pos <- which(namesx %in% namesnull)

      n <- dim(data)[1]

      #the response variable for the C code
      Y <- lmnull$residuals

      #Design matrix of the null model
      X0 <- lmnull$x
      P0 <-
        X0 %*% (solve(t(X0) %*% X0)) %*% t(X0)#Intentar mejorar aprovechando lmnull
      knull <- dim(X0)[2]

      #matrix containing the covariates from which we want to select
			#Factors:						
      X1<- X.full[, -fixed.pos] #before:X1 <- lmfull$x[, -fixed.pos]

      if (dim(X1)[1] < n) {
        stop("NA values found for some of the competing variables")
      }

      #Design matrix for the C-code
      X <- (diag(n) - P0) %*% X1 #equivalent to X<- (I-P0)X
      namesx <- dimnames(X)[[2]]
      if (namesx[1] == "(Intercept)") {
        namesx[1] <-
          "Intercept" #namesx contains the name of variables including the intercept
      }

      p <- dim(X)[2]#Number of covariates to select from

    }

    #If no fixed covariates considered
    if (is.null(fixed.cov)) {
      #Check that all the fixed covariables are included in the full model
      lmfull = lm(formula, data, y = TRUE, x = TRUE)
      X.full <- lmfull$x
      namesx <- dimnames(X.full)[[2]]
      #remove the brackets in "(Intercept)" if present.
      if (namesx[1] == "(Intercept)") {
        namesx[1] <-
          "Intercept" #namesx contains the name of variables including the intercept
      }


      X <- lmfull$x
      knull <- 0
      Y <- lmfull$y
      p <- dim(X)[2]
      n <- dim(X)[1]
      #check if the number of models to save is correct
    }

		#Factors:
		#positions is a matrix with number of rows equal to the number of regressors
		#(either factor or numeric) and number of columns the number of columns of X
		#Each row describes the position (0-1) in X of a regressor (several positions in case
		#this regressor is a factor)
		depvars<- attr(lmfull$terms, "term.labels")
		positions<- matrix(0, ncol=p, nrow=length(depvars))
		for (i in 1:length(depvars)){positions[i,]<- grepl(depvars[i], colnames(X), fixed=T)}
		#positionsX is a vector of the same length as columns has X
		#with 1 in the position with a numeric variable:
		positionsx<- as.numeric(!grepl("factor(", colnames(X), fixed=T))
		write(positionsx, ncolumns=1, file = paste(wd, "/positionsx.txt", sep = ""))
    write(t(positions),
          ncolumns = p,
          file = paste(wd, "/positions.txt", sep = ""))
	  #both files are used to obtain prior probabilities and rank of matrices
		rownames(positions)<- depvars

    #write the data files in the working directory
    write(Y,
          ncolumns = 1,
          file = paste(wd, "/Dependent.txt", sep = ""))
    write(t(X),
          ncolumns = p,
          file = paste(wd, "/Design.txt", sep = ""))

    #The initial model:
    if (is.character(init.model) == TRUE) {
      im <- substr(tolower(init.model), 1, 1)
      if (im != "n" &&
          im != "f" && im != "r") {
        stop("Initial model not valid\n")
      }
      if (im == "n") {
        init.model <- rep(0, p)
      }
      if (im == "f") {
        init.model <- rep(1, p)
      }
      if (im == "r") {
        init.model <- rbinom(n = p,
                             size = 1,
                             prob = .5)
      }
    }
    else{
      init.model <- as.numeric(init.model > 0)
      if (length(init.model) != p) {
        stop("Initial model with incorrect length\n")
      }
    }

    write(
      init.model,
      ncolumns = 1,
      file = paste(wd, "/initialmodel.txt", sep = "")
    )

    #Info:
    cat("Info. . . .\n")
    cat("Most complex model has", p + knull, "covariates\n")
    if (!is.null(fixed.cov)) {
      if (knull > 1) {
        cat("From those",
            knull,
            "are fixed and we should select from the remaining",
            p,
            "\n")
      }
      if (knull == 1) {
        cat("From those",
            knull,
            "is fixed and we should select from the remaining",
            p,
            "\n")
      }
      cat(paste(paste(
        namesx, collapse = ", ", sep = ""
      ), "\n", sep = ""))
    }
    cat("The problem has a total of", 2 ^ (p), "competing models\n")
    iter <- n.iter
    cat("Of these,", n.burnin + n.iter, "are sampled with replacement\n")

    cat("Then,",
        floor(iter / n.thin),
        "are kept and used to construct the summaries\n")


    #Note: priorprobs.txt is a file that is needed only by the "User" routine. Nevertheless, in order
    #to mantain a common unified version the source files of other routines also reads this file
    #although they do not use. Because of this we create this file anyway.
      priorprobs <- rep(0, p + 1)
      write(
        priorprobs,
        ncolumns = 1,
        file = paste(wd, "/priorprobs.txt", sep = "")
      )


		#Factors:
		#here the added index "2" makes reference of the hierarchical corresponding prior but only keeping
		#a model of the same class (copies are removed and only the full within each class is kept)
		if (prior.models!="SBSB2" & prior.models!="ConstConst2" & prior.models!="SB2" & prior.models!="Const2")
			{stop("Prior over the model space not supported\n")}
		
		if (prior.models=="SBSB2"){method<- "rSBSB"; cat("Robust and SB-SB are used.\n")}
		if (prior.models=="ConstConst2"){method<- "rConstConst"; cat("Robust and Const-Const are used.\n")}
		if (prior.models=="SB2"){method<- "rSB"; cat("Robust and SB are used.\n")}
		if (prior.models=="Const2"){method<- "rConst"; cat("Robust and Const are used.\n")}
		
    estim.time <- 0
		
    #Call the corresponding function:
    result <- switch(
      method,
      "rSBSB" = .C(
        "GibbsRobustFSBSB",
        as.character(""),
        as.integer(n),
        as.integer(p),
        as.integer(floor(n.iter / n.thin)),
        as.character(wd),
        as.integer(n.burnin),
        as.double(estim.time),
        as.integer(knull),
        as.integer(n.thin),
        as.integer(seed)
      ),
      "rConstConst" = .C(
        "GibbsRobustFConstConst",
        as.character(""),
        as.integer(n),
        as.integer(p),
        as.integer(floor(n.iter / n.thin)),
        as.character(wd),
        as.integer(n.burnin),
        as.double(estim.time),
        as.integer(knull),
        as.integer(n.thin),
        as.integer(seed)
      ),
      "rSB" = .C(
        "GibbsRobustFSB",
        as.character(""),
        as.integer(n),
        as.integer(p),
        as.integer(floor(n.iter / n.thin)),
        as.character(wd),
        as.integer(n.burnin),
        as.double(estim.time),
        as.integer(knull),
        as.integer(n.thin),
        as.integer(seed)
      ),
      "rConst" = .C(
        "GibbsRobustFConst",
        as.character(""),
        as.integer(n),
        as.integer(p),
        as.integer(floor(n.iter / n.thin)),
        as.character(wd),
        as.integer(n.burnin),
        as.double(estim.time),
        as.integer(knull),
        as.integer(n.thin),
        as.integer(seed)
      ))

    time <- result[[7]]


    #read the files given by C
    models <- as.vector(t(read.table(paste(wd,"/MostProbModels",sep=""),colClasses="numeric")))
    incl <- as.vector(t(read.table(paste(wd,"/InclusionProb",sep=""),colClasses="numeric")))
    joint <- as.matrix(read.table(paste(wd,"/JointInclusionProb",sep=""),colClasses="numeric"))
    dimen <- as.vector(t(read.table(paste(wd,"/ProbDimension",sep=""),colClasses="numeric")))
    betahat<- as.vector(t(read.table(paste(wd,"/betahat",sep=""),colClasses="numeric")))
    allmodels<- as.matrix(read.table(paste(wd,"/AllModels",sep=""),colClasses="numeric"))
    allBF<- as.vector(t(read.table(paste(wd,"/AllBF",sep=""),colClasses="numeric")))


    #Log(BF) for every model
    modelslBF<- cbind(allmodels, log(allBF))
    colnames(modelslBF)<- c(namesx, "logBFi0")
	
    #Now the resampling to obtain models with the "2" priors:
		#if (prior.models=="SBSB2"){modelslBF<- resamplingSBSB(modelslBF, positions)}
		#if (prior.models=="ConstConst2"){modelslBF<- resamplingConstConst(modelslBF, positions)}
		#if (prior.models=="SB2"){modelslBF<- resamplingSB(modelslBF, positions)}
		#if (prior.models=="Const2"){modelslBF<- resamplingConst(modelslBF, positions)}
		

    #Highest probability model
    mod.mat <- as.data.frame(t(models))


    inclusion <- incl
    names(inclusion) <- namesx
    result <- list()
    #
    result$time <- time #The time it took the programm to finish
    result$lmfull <- lmfull # The lm object for the full model
    if(!is.null(fixed.cov)){
      result$lmnull <- lmnull # The lm object for the null model
    }

    result$variables <- namesx #The name of the competing variables
    result$n <- n #number of observations
    result$p <- p #number of competing variables
    result$k <- knull#number of fixed covariates
    result$HPMbin <- models#The binary code for the HPM model
    names(result$HPMbin) <- namesx
    #result$modelsprob <- mod.mat
    result$modelslogBF <-modelslBF#The binary code for all the visited models (after n.thin is applied) and the correspondent log(BF)
    result$inclprob <- inclusion #inclusion probability for each variable
    names(result$inclprob) <- namesx

    result$jointinclprob <- data.frame(joint[1:p,1:p],row.names=namesx)#data.frame for the joint inclusion probabilities
    names(result$jointinclprob) <- namesx
    #
    result$postprobdim <- dimen #vector with the dimension probabilities.
    names(result$postprobdim) <- (0:p)+knull #dimension of the true model
		
		result$positions<- positions
		result$positionsx<- positionsx
		
    #
    #result$betahat <- betahat
    #rownames(result$betahat)<-namesx
    #names(result$betahat) <- "BetaHat"
    result$call <- match.call()

    result$priorprobs <- "En obras"
    result$method <- "gibbs"
    class(result)<- "BvsF"
    result


  }
	
	#' Summary of an object of class \code{BvsF}
	#'
	#' Summary of an object of class \code{BvsF}, providing inclusion probabilities and a representation of
	#' the Median Probability Model and the Highest Posterior probability Model.
	#'
	#' @export
	#' @param object An object of class \code{BvsF}
	#' @param ... Additional parameters to be passed
	#' @author Gonzalo Garcia-Donato and Anabel Forte
	#'
	#'   Maintainer: <anabel.forte@@uv.es>
	#' @seealso See \code{\link[BayesVarSel]{Bvs}},
	#'   \code{\link[BayesVarSel]{GibbsBvs}} for creating objects of the class
	#'   \code{Bvs}.
	#' @examples
	#'
	#'
	
	summary.BvsF <-
	  function(object,...){

	    #we use object because it is requiered by S3 methods
	    z <- object
	    p <- z$p
	    if (!inherits(object, "BvsF"))
	      warning("calling summary.Bvs(<fake-Bvs-x>) ...")
	    ans <- list()
	    #ans$coefficients <- z$betahat
	    #dimnames(ans$coefficients) <- list(names(z$lm$coefficients),"Estimate")

	    HPM <- z$HPMbin
	    MPM <- as.numeric(z$inclprob >= 0.5)
	    astHPM <- matrix(" ", ncol = 1, nrow = p)
	    astMPM <- matrix(" ", ncol = 1, nrow = p)
	    astHPM[HPM == 1] <- "*"
	    astMPM[MPM == 1] <- "*"

	    incl.prob <- z$inclprob
			
			incl.prob.factors<- colMeans((object$modelslogBF[,-(object$p+1)]%*%t(object$positions))>0)
			
	    summ.Bvs <- as.data.frame(cbind(round(incl.prob ,digits = 4), astHPM, astMPM))
	    dimnames(summ.Bvs) <- list(z$variables, c("Incl.prob.", "HPM", "MPM"))
			
			summ.BvsF<- as.data.frame(round(incl.prob.factors, digits=4))
			colnames(summ.BvsF)<- "Incl.prob."

	    ans$summary <- summ.Bvs
			ans$summaryF<- summ.BvsF
	    ans$method <- z$method
	    ans$call <- z$call

	    cat("\n")
	    cat("Call:\n")
	    print(ans$call)
	    cat("\n")
	    cat("Inclusion Probabilities:\n")
	    print(ans$summary)
	    cat("---\n")
			cat("Inclusion Probabilities of factors:\n")
			print(ans$summaryF)
	    cat("---\n")
			
	    cat("Code: HPM stands for Highest posterior Probability Model and\n MPM for Median Probability Model.\n ")
	    if (ans$method == "gibbs") {
	      cat("Results are estimates based on the visited models.\n")
	    }
	    class(ans) <- "summary.Bvs"
	    return(invisible(ans))
	  }
	