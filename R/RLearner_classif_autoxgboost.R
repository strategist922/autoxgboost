#'@export
makeRLearner.classif.autoxgboost = function() {
  makeRLearnerClassif(
    cl = "classif.autoxgboost",
    package = "xgboost",
    par.set = makeParamSet(
      # we pass all of what goes in 'params' directly to ... of xgboost
      # makeUntypedLearnerParam(id = "params", default = list()),
      makeNumericLearnerParam(id = "eta", default = 0.3, lower = 0, upper = 1),
      makeNumericLearnerParam(id = "gamma", default = 0, lower = 0),
      makeIntegerLearnerParam(id = "max_depth", default = 6L, lower = 1L),
      makeNumericLearnerParam(id = "min_child_weight", default = 1, lower = 0),
      makeNumericLearnerParam(id = "subsample", default = 1, lower = 0, upper = 1),
      makeNumericLearnerParam(id = "colsample_bytree", default = 1, lower = 0, upper = 1),
      makeNumericLearnerParam(id = "colsample_bylevel", default = 1, lower = 0, upper = 1),
      makeIntegerLearnerParam(id = "num_parallel_tree", default = 1L, lower = 1L),
      makeNumericLearnerParam(id = "lambda", default = 0, lower = 0),
      makeNumericLearnerParam(id = "lambda_bias", default = 0, lower = 0),
      makeNumericLearnerParam(id = "alpha", default = 0, lower = 0),
      makeUntypedLearnerParam(id = "objective", default = "binary:logistic", tunable = FALSE),
      makeUntypedLearnerParam(id = "eval_metric", default = "error", tunable = FALSE),
      makeNumericLearnerParam(id = "base_score", default = 0.5, tunable = FALSE),
      makeIntegerLearnerParam(id = "early_stopping_rounds", default = 1, lower = 1L, tunable = FALSE)
    ),
    properties = c("twoclass", "multiclass", "numerics", "factors", "prob", "weights"),
    name = "eXtreme Gradient Boosting",
    short.name = "autoxgboost",
    note = "All settings are passed directly, rather than through `xgboost`'s `params` argument. `nrounds` has been set to `1` and `verbose` to `0` by default. `num_class` is set internally, so do not set this manually."
  )
}

#' @export
trainLearner.classif.autoxgboost = function(.learner, .task, .subset, .weights = NULL, objective, eval_metric, early_stopping_rounds, ...) {
  
  td = getTaskDescription(.task)
  nc = length(td$class.levels)
  parlist = list(...)
  parlist$eval_metric = eval_metric
  
  rdesc = makeResampleDesc("Holdout", stratify = TRUE, split = 4/5)
  rinst = makeResampleInstance(rdesc, .task)
  train.inds = rinst$train.inds[[1]]
  test.inds = rinst$test.inds[[1]]
  
  if (is.null(.weights)) {
    watchlist = list(eval = createDMatrixFromTask(subsetTask(.task, test.inds)))
    data = createDMatrixFromTask(subsetTask(.task, train.inds))
  } else {
    watchlist = list(eval = createDMatrixFromTask(subsetTask(.task, test.inds), 
      weights = .weights[test.inds]))
    data = createDMatrixFromTask(subsetTask(.task, train.inds),
      weights = .weights[train.inds])
  }
  if (is.null(objective))
    objective = ifelse(nc == 2L, "binary:logistic", "multi:softprob")
  
  if (.learner$predict.type == "prob" && objective == "multi:softmax")
    stop("objective = 'multi:softmax' does not work with predict.type = 'prob'")
  
  mod = xgboost::xgb.train(params = parlist, data = data, nrounds = 10^2, watchlist = watchlist,
    objective = objective, early_stopping_rounds = early_stopping_rounds, silent = 1L, verbose = 0L)
  
  mod$test.inds = test.inds
  
  return(mod)
}

#' @export
predictLearner.classif.autoxgboost = function(.learner, .model, .newdata, ...) {
  td = .model$task.desc
  m = .model$learner.model
  cls = td$class.levels
  nc = length(cls)
  obj = .learner$par.vals$objective
  
  if (is.null(obj))
    .learner$par.vals$objective = ifelse(nc == 2L, "binary:logistic", "multi:softprob")
  
  p = predict(m, newdata = data.matrix(.newdata), ...)
  
  if (nc == 2L) { #binaryclass
    if (.learner$par.vals$objective == "multi:softprob") {
      y = matrix(p, nrow = length(p) / nc, ncol = nc, byrow = TRUE)
      colnames(y) = cls
    } else {
      y = matrix(0, ncol = 2, nrow = nrow(.newdata))
      colnames(y) = cls
      y[, 1L] = 1 - p
      y[, 2L] = p
    }
    if (.learner$predict.type == "prob") {
      return(y)
    } else {
      p = colnames(y)[max.col(y)]
      names(p) = NULL
      p = factor(p, levels = colnames(y))
      return(p)
    }
  } else { #multiclass
    if (.learner$par.vals$objective  == "multi:softmax") {
      return(factor(p, levels = cls)) #special handling for multi:softmax which directly predicts class levels
    } else {
      p = matrix(p, nrow = length(p) / nc, ncol = nc, byrow = TRUE)
      colnames(p) = cls
      if (.learner$predict.type == "prob") {
        return(p)
      } else {
        ind = max.col(p)
        cns = colnames(p)
        return(factor(cns[ind], levels = cns))
      }
    }
  }
}