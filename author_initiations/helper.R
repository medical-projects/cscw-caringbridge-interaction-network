# original source: https://github.com/janovergoor/choose2grow/blob/94c9bfeb47bd51e7c9b4cfdd0daaa8736bef31d9/reports/helper.R

suppressPackageStartupMessages(library(ggplot2))

library(ggplot2)
library(latex2exp)
library(mlogit)
library(stringr)
library(parallel)
library(tidyr)
library(readr)
library(scales)
library(dplyr)
library(gridExtra)


# cleaner theme
my_theme <- function(base_size=11) {
  # Set the base size
  theme_bw(base_size=base_size) +
    theme(
      # Center title
      plot.title = element_text(hjust=0.5),
      # Make the background white, with open top-right
      panel.grid.major=element_blank(),
      panel.grid.minor=element_blank(),
      axis.line=element_line(colour="black"),
      panel.border=element_blank(),
      panel.background=element_blank(),
      # Minimize margins
      plot.margin=unit(c(0.2, 0.2, 0.2, 0.2), "cm"),
      panel.spacing=unit(0.25, "lines"),
      # Tiny space between axis labels and tick labels
      axis.title.x=element_text(margin=ggplot2::margin(t=6.0)),
      axis.title.y=element_text(margin=ggplot2::margin(r=6.0)),
      # Simplify the legend
      legend.title=element_blank(),
      legend.key=element_blank(),
      legend.background=element_rect(fill='transparent')
    )
}

# read plfit from external source
# we don't actually use this
#source("http://tuvalu.santafe.edu/~aaronc/powerlaws/plfit.r")

# CDF of power law distribution
cdf <- Vectorize(function(x, a, xmin){
  (x/xmin)^(-a+1)
})

# approximate Zeta function
my_zeta <- Vectorize(function(a, xmin) {
  sum((0:100000 + xmin)^(-a))
})

# plot a inverse CDF of a degree distribution with a power law fit overlaid
plot_powerlaw_cdf <- function(X, title, xlab, ylab) {
  fit <- plfit(X, "range", seq(1.001,4,0.01))
  print(sprintf("plfit:  alpha=%.3f  xmin=%d", fit$alpha, fit$xmin))
  DF <- data.frame(x=1:max(X)) %>%
    left_join(data.frame(x=X) %>% group_by(x) %>% summarize(n=n()), by='x') %>%
    mutate(n=ifelse(is.na(n), 0, n)) %>%
    mutate(p=(sum(n)-cumsum(n))/sum(n))
  ggplot(DF, aes(x, p)) + geom_point() +
    ggtitle(title) +
    scale_x_log10(xlab, breaks=c(1,10,100,1000), labels=trans_format('log10', math_format(10^.x))) +
    scale_y_log10(ylab, breaks=c(10e-1, 10e-2, 10e-3, 10e-4, 10e-5, 10e-6), labels=trans_format('log10', math_format(10^.x))) +
    geom_line(data=data.frame(x=fit$xmin:max(X)) %>% mutate(p=cdf(x, fit$alpha, fit$xmin)*DF$p[fit$xmin]), color='red') +
    my_theme()
}

# compute Jackson's r on a degree distribution
# based on code by Eduardo Muggenburg
r_jackson <- function(deg_dist, m, tol=0.00000001 , r0=1.3, r1=1.7, max_iter=500){
  LHS <- log(1 - deg_dist + 0.000001)
  delta <- abs(r0 - r1)
  degrees <- 1:length(deg_dist)
  k <- 1
  while(delta > tol & k < max_iter){
    RHS <- log(degrees + r0 * m)
    f <- lm(LHS ~ 0 + RHS)
    r_tmp <- summary(f)$coefficients[1,1]
    r1 <- (-1*r_tmp)-1
    delta <- abs(r0 - r1)
    r0 <- r1
    k <- k + 1
  }
  r1
}

# compute the accuracy of a model on new data
# note this function was edited by Zach L to specify the outcome name as "is_target"
acc <- function(f, data) {
  # compute predictions
  P <- predict(f, newdata=data) %>% as.data.frame()
  dp <- P %>% mutate(choice_id=rownames(P)) %>% gather(choice, score, -choice_id)
  inner_join(
    # actuals
    data %>% filter(is_target) %>% select(choice_id, correct=alt_id) %>% mutate(choice_id=as.character(choice_id)),
    # predicted
    dp %>%
      # sort by score and random to break ties randomly
      mutate(r=runif(nrow(dp))) %>% group_by(choice_id) %>% arrange(-score, r) %>%
      # take highest score
      mutate(n=row_number()) %>% filter(n==1),
    by='choice_id'
  ) %>% ungroup() %>%
    summarize(acc=mean(choice==correct)) %>% .$acc %>% as.numeric()
}

original_log <- log
min_val <- 1e-100
log_min_val <- original_log(min_val)
# version of log that returns 0 if input is 0
mindefined_censored_log <- Vectorize(function(x, min=min_val, max=NA) {
  if(is.na(x)) return(0)
  if(!is.na(min) & x < min) return(log_min_val)
  if(!is.na(max) & x > max) return(0)
  return(original_log(x))
})

# version of log that returns 0 if input is 0
censored_log <- Vectorize(function(x, min=NA, max=NA) {
  if(is.na(x)) return(0)
  if(!is.na(min) & x < min) return(0)
  if(!is.na(max) & x > max) return(0)
  return(log(x))
})

# likelihood-ratio test
lrt <- function(ll0, ll1, df=1) {
  pchisq(2*abs(ll1-ll0), df=df, lower.tail=F)
}
