#' Correction for p>>n for an object of class \code{Bvs}
#'
#' In cases where p>>n and the true model is expected to be sparse, it is very unlikely that the Gibbs sampling
#' will not sample models in the singular set of the model space (models with k>n). Nevertheless, depending on
#' how large is p/n and the strenght of the signal, this part of the model space could be very influential in the
#' final response. 
#' 
#' This function provides an estimation of the posterior probability of models with k>n which is a measure of the 
#' importance of these models. In summary, if this probability is large, implies that the n is not large enough to beat
#' such large p.
#' Additionally, \code{pltltn} gives corrections of the posterior inclusion probabilities and posterior probabilities 
#' of dimension of the true model.
#'
#' @export
#' @param object An object of class \code{Bvs} obtained with \code{GibbsBvs}
#' @author Gonzalo Garcia-Donato
#'
#'   Maintainer: <gonzalo.garciadonato@uclm.es>
#' @seealso See 
#'   \code{\link[BayesVarSel]{GibbsBvs}} for creating objects of the class
#'   \code{Bvs}.
#' @examples
#'
#' \dontrun{
#' #Analysis of Crime Data
#' #load data
#' data(UScrime)
#'
#' #Default arguments are Robust prior for the regression parameters
#' #and constant prior over the model space
#' #Here we keep the 1000 most probable models a posteriori:
#' crime.Bvs<- Bvs(formula= y ~ ., data=UScrime, n.keep=1000)
#'
#' #A look at the results:
#' summary(crime.Bvs)
#' }
#'
pltltn<- function(object){
	#Corrected posterior inclusion probabilities and probabilities of dimension
	#for the case where p>>n.
	#Ms=model space with singular models; Mr=model space with regular models
  if (!inherits(object, "Bvs"))
    stop("calling summary.Bvs(<fake-Bvs-x>) ...")
	
	if (object$method != "gibbs") 
		stop("This corrected estimates are for Gibbs sampling objects.")
	
	#The method weitghs results on Mr (provided by Gibbs sampling) with those in Ms (theoretical)
	
	#first obtain the estimates conditionall on Mr
	kgamma<- rowSums(object$modelslogBF[,1:object$p])
	isMr<- kgamma < object$n-length(object$lmnull$coefficients)
	inclprobMr<- colMeans(object$modelslogBF[isMr,1:object$p])
	postprobdimMr<- table(kgamma[isMr])/sum(isMr)
	names(postprobdimMr)<- as.numeric(names(postprobdimMr))+length(object$lmnull$coefficients)
		
	#ratio of prior probabilities of Ms to Mr
	qSR<- sum(object$priorprobs[(object$n+1):(object$p+1)]*choose(object$p,   					object$n:object$p))/sum(object$priorprobs[1:object$n]*choose(object$p, 0:(object$n-1)))
	#The posterior probabililty of Ms:
	pS<- qSR/(qSR+object$C)
	cat(paste("Estimate of the posterior probability of the\n model space with singular models is:", round(pS,3),"\n"))

	#Corrected posterior probability over the dimension:
	postprobdim<- postprobdimMr*(1-pS)
	#Corrected inclusion probabilities:
	inclprob<- inclprobMr*(1-pS) + 0.5*pS
	result<- list()
	result$pS<- pS
	result$postprobdim<- postprobdim
	result$inclprob<- inclprob
	return(result)
}

