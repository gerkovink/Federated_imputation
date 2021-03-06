
library(mice) # imputations
library(tidyverse) # tidy data
library(modelr) # bootstrap
library(magrittr) # pipe
library(furrr) # parallel mapping

set.seed(123) # seed for reproducibility

#create one complete dataset that allow us to work without missings
truth <- boys %>% mice(seed = 123, m = 1, print = FALSE) %>% complete()

# shorten the complete lm model, since we want to use the same model anyhow
model <- function(data) lm(wgt ~ age + hgt, data)

# run this model
truemodel <- truth %>% model

# extract the coefficients
coefs <- coef(truemodel)

# parallel processing to increase speed
plan(multisession)

# number of iterations
nsim <- 500

# default method - pmm for all continuous predictors
def <- rep("pmm", ncol(truth))
# add the variable names
names(def) <- colnames(truth)
# impute bmi passively
def['bmi'] <- "~I(wgt / (hgt/100)^2)"
# set gen and phb to proportional odds model
def[c('gen', 'phb')] <- "polr"
# set reg to polytomous logistic regression
def['reg'] <- "polyreg"

# cart method, all variables are imputed by means of cart
cart <- rep("cart", ncol(truth))
names(cart) <- colnames(truth)
cart['bmi'] <- "~I(wgt / (hgt/100)^2)"

# alter the predictor matrix such that imputations for bmi do not flow
# back into the predictions for wgt and hgt
pred <- make.predictorMatrix(truth)
pred[c("wgt", "hgt"), "bmi"] <- 0

# create the default synthetic datasets
syns_def <- future_map(1:nsim, ~ {
  truth %>% mice(m = 5, 
                 method = def, 
                 predictorMatrix = pred, 
                 where = matrix(TRUE, nrow(truth), ncol(truth)), 
                 print = F)
}, .options = future_options(seed = as.integer(123)), .progress = TRUE, .id = "syn")

# create the synthetic datasets by means of cart
syns_cart <- future_map(1:nsim, ~ {
  truth %>% mice(m = 5, 
                 method = cart,
                 predictorMatrix = pred,
                 where = matrix(TRUE, nrow(truth), ncol(truth)),
                 print = F)
}, .options = future_options(seed = as.integer(123)), .progress = TRUE, .id = "syn")

# change the order of height and weight
cart_wgt_hgt <- future_map(1:nsim, ~ {
  truth %>% mice(m = 5,
                 method = cart,
                 predictorMatrix = pred,
                 where = matrix(TRUE, nrow(truth), ncol(truth)),
                 visitSequence = c('age', 'wgt', 'hgt', 'bmi', 'hc', 'gen', 'phb', 'tv', 'reg'),
                 print = F)
}, .options = future_options(seed = as.integer(123)), .progress = T, .id = "syn")

# change cart settings (maxit = 1, minbucket = 3, cp = 1e-08), so that the variance
# in the imputed datasets increases (and hopefully the bias decreases).
syns_cart_maxit_cp_min3 <- future_map(1:nsim, ~ {
  truth %>% mice(m = 5,
                 maxit = 1,
                 method = cart,
                 minbucket = 3,
                 cp = 1e-08,
                 predictorMatrix = pred,
                 where = matrix(TRUE, nrow(truth), ncol(truth)),
                 print = F)
}, .options = future_options(seed = as.integer(123)), .progress = TRUE)

# create nsim bootstrapped datasets
bootstrap_boys <- bootstrap(truth, nsim) %$% strap %>% map(as.data.frame)

# impute the bootstrapped datasets
boot_cart <- bootstrap_boys %>% 
  future_map(function(x) {
    mice(x, 
         m = 5,
         method = cart,
         predictorMatrix = pred,
         where = matrix(TRUE, nrow(truth), ncol(truth)),
         print = F)
    }, .options = future_options(seed = as.integer(123)), .progress = T)

# impute the bootstrapped boys datasets with parameters that induce more variability
# and hopefully less bias
boot_cart_maxit_cp_min3 <- bootstrap_boys %>%
  future_map(function(x) {
    x %>% mice(m = 5, 
               maxit = 1,
               method = cart,
               minbucket = 3,
               cp = 1e-08,
               predictorMatrix = pred,
               where = matrix(TRUE, nrow(truth), ncol(truth)),
               print = F)
}, .options = future_options(seed = as.integer(123)), .progress = TRUE)

boot_cart_append_maxit1_cp_min3 <- bootstrap_boys %>%
  future_map(function(x) {
    x %>% 
      bind_rows(data.frame(matrix(NA, nrow(.), ncol(.), dimnames = list(NULL, colnames(.))))) %>%
      mice(m = 5,
           maxit = 1,
           method = cart,
           minbucket = 3, 
           cp = 1e-08,
           predictorMatrix = pred,
           print = F)
  }, .options = future_options(seed = as.integer(123)), .progress = TRUE)

boot_cart_append_maxit50_cp_min3 <- bootstrap_boys %>%
  future_map(function(x) {
    x %>% 
      bind_rows(data.frame(matrix(NA, nrow(.), ncol(.), dimnames = list(NULL, colnames(.))))) %>%
      mice(m = 5,
           maxit = 50,
           method = cart,
           minbucket = 3, 
           cp = 1e-08,
           predictorMatrix = pred,
           print = F)
  }, .options = future_options(seed = as.integer(123)), .progress = TRUE)

# Impute the bootstrapped boys datasets similarly to the previous simulations
# but with 5 iterations instead of 1
boot_cart_cp_min3 <- bootstrap_boys %>%
  future_map(function(x) {
    x %>% mice(m = 5, 
               maxit = 5,
               method = cart,
               minbucket = 3,
               cp = 1e-08,
               predictorMatrix = pred,
               where = matrix(TRUE, nrow(truth), ncol(truth)),
               print = F)
  }, .options = future_options(seed = as.integer(123)), .progress = TRUE)

