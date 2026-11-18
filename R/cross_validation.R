# 외부 fold와 기준값 후보를 검증한다. fold 생성이나 재정렬은 수행하지 않는다.
validate_cv_inputs <- function(data, folds, t_values, s_values, number) {
  validate_training_data(data)
  if (!is.list(folds) || !length(folds)) stop("하나 이상의 외부 fold가 필요합니다.")
  for (fold in folds) {
    if (!is.numeric(fold) || !length(fold) || any(!is.finite(fold)) ||
        any(fold != floor(fold)) || any(fold < 1 | fold > nrow(data)) ||
        anyDuplicated(fold) || length(fold) >= nrow(data)) {
      stop("fold에는 중복 없는 유효 행 번호와 비어 있지 않은 학습·평가 집합이 필요합니다.")
    }
  }
  for (values in list(t_values, s_values)) {
    if (!is.numeric(values) || !length(values) || any(!is.finite(values)) || any(values < 0)) {
      stop("병합 기준 후보는 0 이상의 유한한 수치 벡터여야 합니다.")
    }
  }
  validate_tree_parameters(number, t_values[1], s_values[1])
  invisible(TRUE)
}

# 전달된 fold의 MAE 단순 평균으로 병합 기준을 고른다. 기본은 순차 실행이며 전역값을 쓰지 않는다.
cross_validate_merged_tree <- function(data, folds, t_values, s_values, number, parallel = FALSE) {
  validate_cv_inputs(data, folds, t_values, s_values, number)
  act_require_packages(c("rpart", "partykit", "psych", "caret", "foreach"))
  if (!is.logical(parallel) || length(parallel) != 1L || is.na(parallel)) {
    stop("parallel은 단일 TRUE 또는 FALSE여야 합니다.")
  }
  if (parallel && (!foreach::getDoParRegistered() || foreach::getDoParWorkers() < 2L)) {
    stop("병렬 실행은 호출자가 2개 이상의 worker 백엔드를 등록한 뒤 요청해야 합니다.")
  }
  exports <- c("fit_merged_tree", "predict_merged_tree", "validate_training_data",
               "validate_tree_parameters", "validate_response", "act_require_packages",
               "merged_tree_control", "make_tree_node", "merge_tree_nodes", "fit_stump",
               "node_pair_statistic", "merge_stage_nodes")
  iterator <- foreach::foreach(t_value = t_values, .combine = rbind, .inorder = TRUE,
                               .export = exports)
  execute <- if (parallel) foreach::`%dopar%` else foreach::`%do%`
  results <- execute(iterator, {
    errors <- c()
    for (s_value in s_values) {
      fold_errors <- c()
      for (fold in folds) {
        model <- fit_merged_tree(data[-fold, ], number, t_value, s_value)
        predictions <- c()
        for (row in fold) {
          predictions <- c(predictions, predict_merged_tree(model, data[row, , drop = FALSE])$prediction)
        }
        fold_errors <- c(fold_errors, caret::MAE(predictions, data[fold, "score"]))
      }
      errors <- c(errors, mean(fold_errors))
    }
    c(t_value, s_values[which.min(errors)], min(errors))
  })
  results <- as.data.frame(results)
  names(results) <- c("critical.t", "critical.s", "mae")
  best <- which.min(results$mae)
  list(results = results, critical.t = results$critical.t[best], critical.s = results$critical.s[best])
}
