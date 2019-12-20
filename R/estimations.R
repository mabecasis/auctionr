#' Estimates a first-price auction model
#'
#'
#' @param dat data.frame containing input columns in the following order: the winning bids, number of bids, and \code{X} variables that represent observed heterogeneity.
#' @param init_params Vector of initial values for mu, alpha, sigma, and beta vector.
#' @param method Optimization method to be used in optim() (see ?optim for details).
#' @param control A list of control parameters to be passed to optim() (see ?optim for details).
#'
#' @details This function estimates a first-price auction model with conditional independent private values.
#' The model allows for unobserved heterogeneity that is common to all bidders in addition to observable
#' heterogeneity. The winning bid (Y) takes the form
#'
#' Y = B * U * h(X)
#'
#' where B Is the proportional winning bid, U is the unobserved heterogeneity, and h(X) controls for
#' observed heterogeneity. The model is log-linear so that
#' log(Y) = log(B) + log(U) + log(h(X)) and log(h(X)) = beta1 * X1 + beta2 * X2 + … .
#'
#' The (conditionally) independent private costs are drawn from a Weibull distribution
#' with parameters mu and alpha. The CDF of this distribution is given by
#'
#' F(c) = 1 – exp(- (c * 1/mu * Gamma(1 + 1/alpha))^(alpha))
#'
#' The unobserved heterogeneity U is sampled from log-Normal distribution with mean 1 and a free parameter sigma representing its standard deviation.
#'
#' \code{ini_params}, the initial guess for convergence, must be supplied.
#'#'
#' This funtion utilizes the \code{Rsnow} framework within the \code{Rparallel} package. If \code{numcores} is not specified, this will be run using only
#' one CPU/core. One can use \code{parallel::detectCores()} to determine how many are available on your system, but you are not advised
#' to use all at once, as this may make your system unresponsive. Please see \code{Rparallel} and \code{Rsnow} for more details.
#'
#' Note that the supplied data can not have missing values.
#'#'
#' @examples
#'
#' set.seed(100)
#' dat <- auction_generate_data(obs = 1000, mu = 10, alpha = 2, sigma = 0.2, beta = c(-1,1), new_x_mean= c(-1,1), new_x_sd = c(0.5,0.8))
#' auction_model(dat,
#'               init_param =  c(8, 2, .5, .4, .6),
#'               num_cores = 10,
#'               method = "BFGS",
#'               control = list(trace=1, parscale = c(1,0.1,0.1,1,1)))
#'
#' @seealso \code{\link{auction_generate_data}}
#'
#'
#' @import parallel
#' @export

auction_model <- function(dat = NULL,
                          init_param = NULL,
                          num_cores = 1,
                          method = "BFGS",
                          control = list() # list of control parameters for optim()
                          ) {

  library(parallel)

  # Check inputs here!

  v__y = dat[,1]
  v__n = dat[,2]
  m__h_x = dat[,-c(1:2)]

  # Set up parallelization
  cl = makeCluster(num_cores)
  clusterExport(cl, varlist=c("vf__bid_function_fast",
                             "vf__w_integrand_z_fast",
                             "f__funk"))

  #f__ll_parallel(x0, y = v__y, n = v__n, h_x = m__h_x, cl = cl)

  # Run
  result = optim(par=init_param, fn=f__ll_parallel, y=v__y, n=v__n, h_x=m__h_x, cl=cl, method = method, control = control)

  stopCluster(cl)

  # Inspect result
  # Might need to make sure that it is a global solution, try different optim() methods

  # Return result
  return(result)
}


#' Generate example data for running \code{\link{auction_model}}
#'
#'
#' @param obs Number of observations (or auctions) to draw.
#' @param max_n_bids Maximum number of bids per auction. The routine generates a vector of length \code{obs} of random numbers between 2 and max_n_bids.
#' @param new_x_mean Mean values for observable controls to be generated from a Normal distriution.
#' @param new_x_sd Standard deviations for observable controls to be generated from a Normal distriution.

#' @param mu Value for mu, or mean, of private value distribution (Weibull) to be generated.
#' @param alpha Value for alpha, or shape parameter, of private value distribution (Weibull) to be generated.
#' @param sigma Value for standard deviation of unobserved heterogeneity distribution. Note that the distibution is assumed to have mean 1.
#' @param beta Coefficients for the generated observable controls. Must be of the same length as \code{new_x_meanlog} and \code{new_x_sdlog}.
#'
#' @details This function generates example data for feeding into auction_model(). Specifically, the
#' winning bid, number of bids, and observed heterogeneity are sampled for the specified number of observations.
#'
#' @return A data frame with \code{obs} rows and the following columns:
#' \describe{
#' \item{winning_bid}{numeric values of the winning bids for each observation}
#' \item{n_bids}{number of bids  for each observation}
#' \item{obs_X#}{X terms that represent observed heterogeneity}
#'}
#'
#' @examples
#' dat <- auction_generate_data(obs = 100, mu = 10, new_x_mean= c(-1,1), new_x_sd = c(0.5,0.8), alpha = 2, sigma = 0.2, beta = c(-1,1))
#' dim(dat)
#' head(dat)
#'
#' @seealso \code{\link{auction_model}}
#'
#'
#' @export
auction_generate_data <- function(obs = NULL,
                                  max_n_bids = 10,
                                  new_x_mean = NULL,
                                  new_x_sd = NULL,
                                  mu = NULL,
                                  alpha = NULL,
                                  sigma = NULL,
                                  beta = NULL) {
  # Inspect parameters
  # Must specify (mu, alpha, sigma, beta)
  # if max_n_bids isn't provided, set to 10
  # new_x_meanlog and new_x_sdlog must be of the same length as beta or scalar
  # Inspect new_x_meanlog and new_x_sdlog
  #'new_x_sdlog' must be numeric vector,
  #      of same length as 'new_x_meanlog'

  # Generate number of bids for every auction
  n_bids = sample(2:max_n_bids, obs, replace=TRUE)
  gamma_1p1oa = gamma(1 + 1/alpha)

  # Winning cost is taken as a minimum of n_bids independent r.v's distributed as Weibull
  # Then a proportional bid function is applied to the winning cost
  v.w_bid = rep(NA, obs)

  for(i in 1:obs){
    costs = (mu/gamma(1+1/alpha))*(-log(1-stats::runif(n_bids[i])))^(1/alpha)

    v.w_bid[i] = vf__bid_function_fast(cost=min(costs),
                                   num_bids=n_bids[i],
                                   mu=mu,
                                   alpha=alpha,
                                   gamma_1p1oa=gamma_1p1oa)
  }

  # Unobserved heterogeneity
  sigma_lnorm = sqrt(log(1+sigma^2))
  v.u = rlnorm(n = obs, meanlog=(-sigma_lnorm^2*1/2), sdlog = sigma_lnorm)

  # Observed heterogeneity
  all_x_vars = auction__generate_x(obs = obs,
                                   new_x_mean = new_x_mean,
                                   new_x_sd = new_x_sd)

  # Calculate winning bid
  v.h_x = exp(colSums(beta*t(all_x_vars)))
  v.winning_bid = v.w_bid*v.u*v.h_x

  dat = data.frame(winning_bid = v.winning_bid, n_bids = n_bids, all_x_vars)

  return(dat)
}


# Observed heterogeneity
auction__generate_x <- function(obs,
                                new_x_mean,
                                new_x_sd) {
  # Generate new_x_vars
  new_x_vars = matrix(NA, obs, length(new_x_mean))
  new_x_num = length(new_x_mean)

  for (i.new_x in 1:new_x_num) {
      new_x_vars[, i.new_x] = rnorm(obs,
                                   mean = new_x_mean[i.new_x],
                                   sd = new_x_sd[i.new_x])
  }

  colnames(new_x_vars) = paste0("obs_X",1:new_x_num)

  return(new_x_vars)
}


vf__bid_function_fast = function(cost, num_bids, mu, alpha, gamma_1p1oa) {

  ifelse (exp(-(num_bids-1)*(1/(mu/gamma_1p1oa)*cost)^alpha) == 0,

          cost + mu/alpha*(num_bids-1)^(-1/alpha)*1/gamma_1p1oa*
            ((num_bids-1)*(gamma_1p1oa/mu*cost)^alpha)^(1/alpha-1),

          cost + 1/alpha*(mu/gamma_1p1oa)*(num_bids-1)^(-1/alpha)*
            pgamma((num_bids-1)*(1/(mu/gamma_1p1oa)*cost)^alpha, 1/alpha, lower=FALSE)*
            gamma(1/alpha)* # Check gamma(1/alpha) part
            1/exp(-(num_bids-1)*(1/(mu/gamma_1p1oa)*cost)^alpha)
  )
}


vf__w_integrand_z_fast = function(z, w_bid, num_bids, mu, alpha, gamma_1p1oa,sigma_u) {

  b_z = vf__bid_function_fast(cost=z, num_bids=num_bids, mu=mu, alpha=alpha, gamma_1p1oa)
  u_z = w_bid/b_z

  sigma_lnorm = sqrt(log(1+sigma_u^2))

  vals = num_bids*alpha*(gamma_1p1oa/mu)^alpha*z^(alpha-1)*
    exp(-num_bids*(gamma_1p1oa/mu*z)^alpha)*
    1/b_z*
    dlnorm(u_z, meanlog=(-sigma_lnorm^2*1/2), sdlog = sigma_lnorm) # Note: can swap for different distributions

  # ensuring that really large and small values do not throw errors
  vals[(gamma_1p1oa/mu)^alpha == Inf] = 0
  vals[exp(-num_bids*(gamma_1p1oa/mu*z)^alpha) == 0] = 0

  return(vals)
}


f__funk = function(data_vec, sigma_u) {
  #
  val = integrate(vf__w_integrand_z_fast, w_bid=data_vec[1],
                  num_bids=data_vec[2], mu=data_vec[3], alpha=data_vec[4],
                  gamma_1p1oa=data_vec[5], sigma_u=sigma_u, lower=0, upper=Inf)

  if(val$message != "OK") stop("Integration failed.")

  return(val$value)
}


f__ll_parallel = function(x0, y, n, h_x, cl) {
  #
  params = x0
  v__y = y
  v__n = n
  m__h_x = h_x

  v__mu = params[1]
  v__alpha = params[2]
  u = params[3]

  h = params[4:( 3 + dim(m__h_x)[2] )]
  v__h = exp( colSums( h * t(m__h_x) ) )

  if (u <= 0.01) return(-Inf) # Check that these hold at estimated values
  if (v__mu <= 0) return(-Inf)
  if (v__alpha <= 0.01) return(-Inf)

  # Y Component
  v__gamma_1p1opa = gamma(1 + 1/v__alpha)
  v__w = v__y / v__h
  dat = cbind(v__w, v__n, v__mu, v__alpha, v__gamma_1p1opa)

  v__f_w = parApply(cl = cl, X = dat, MARGIN = 1, FUN = f__funk, sigma_u = u)
  v__f_y = v__f_w / v__h

  return(-sum(log(v__f_y)))
}