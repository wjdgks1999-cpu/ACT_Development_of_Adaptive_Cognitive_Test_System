# 저장소 루트에서 실행한다. Git 원본과 합성자료를 메모리에서 비교하며 실제자료를 읽지 않는다.
source("R/config.R", encoding = "UTF-8")
source("R/merged_tree.R", encoding = "UTF-8")
source("R/cross_validation.R", encoding = "UTF-8")
source("examples/synthetic_data.R", encoding = "UTF-8")
act_require_packages(c("rpart", "party", "partykit", "psych", "caret", "foreach", "doParallel"))
suppressPackageStartupMessages({
  library(caret)
  library(rpart)
  library(party)
  library(partykit)
  library(psych)
  library(foreach)
})
foreach::registerDoSEQ()

checks <- 0L
# 값·속성 차이를 수치 허용오차 없이 비교하고 실패한 항목을 보고한다.
check_equal <- function(actual, expected, label) {
  comparison <- all.equal(actual, expected, tolerance = 0)
  if (!isTRUE(comparison)) stop(label, ": ", paste(comparison, collapse = "; "))
  checks <<- checks + 1L
  invisible(TRUE)
}

# 지원하지 않는 입력이 성공으로 바뀌지 않았는지 확인한다.
check_error <- function(expression, label) {
  result <- tryCatch(force(expression), error = identity)
  if (!inherits(result, "error")) stop(label, ": 오류가 발생하지 않았습니다.")
  checks <<- checks + 1L
  conditionMessage(result)
}

# 고정된 Git 커밋의 원본을 읽는다. 네트워크 조회나 별도 호환 파일은 필요하지 않다.
read_baseline <- function() {
  commit <- "6e77f884217efc47d1d55a496e360592e76165e9"
  args <- c("-c", shQuote(paste0("safe.directory=", normalizePath(".", winslash = "/"))),
            "show", shQuote(paste0(commit, ":Merged_Decision_Tree_구현_Code.r")))
  lines <- system2("git", args, stdout = TRUE)
  if (!is.null(attr(lines, "status"))) stop("기준 커밋을 읽을 수 없습니다.")
  parse(text = lines, encoding = "UTF-8")
}

# 원본 함수를 격리 환경에 올린다. 원본 <<-의 쓰기 대상은 테스트 전용 환경으로 제한한다.
baseline_environment <- function(expressions) {
  env <- new.env(parent = globalenv())
  env$merged.tree <- NULL
  env$now <- env$now.pred <- env$now.stage <- NULL
  env$cv.result <- env$final.t <- env$final.s <- NULL
  eval(expressions, envir = env)
  env
}

# 원본 예측 함수에 관찰만 추가해 분기·병합 경로를 기록한다. 조건과 계산식은 바꾸지 않는다.
instrument_prediction <- function(fun) {
  code <- paste(deparse(fun), collapse = "\n")
  code <- sub("now <- 1", "now <- 1; observed_path <- now; observed_items <- character()", code, fixed = TRUE)
  code <- sub("split.varid <-", "observed_items <- c(observed_items, as.character(merged.tree[[canbenext[1]]][[3]][1])); split.varid <-", code, fixed = TRUE)
  code <- gsub("now <- j", "now <- j; observed_path <- c(observed_path, now)", code, fixed = TRUE)
  code <- gsub("now <- m", "now <- m; observed_path <- c(observed_path, now)", code, fixed = TRUE)
  code <- sub("now.stage <<- now.stage", "now.stage <<- now.stage; list(path = observed_path, items = observed_items)", code, fixed = TRUE)
  eval(parse(text = code), envir = environment(fun))
}

expressions <- read_baseline()
baseline <- baseline_environment(expressions)
observed_predict <- instrument_prediction(baseline$predict.merge)
set.seed(9127)
data <- make_synthetic_data()
adverse <- data
adverse$score <- -8 * data$q1 + 3 * data$q2 + data$q3 + stats::rnorm(nrow(data), sd = 0.2)
ties <- data
ties$score <- with(data, q1 + q2 + q3 + q4 + q5) + rep(c(-0.1, 0.1), length.out = nrow(data))
cases <- list(
  no_merge = list(data, 3, 0, 0),
  t_merge = list(data, 3, 20, 0),
  d_merge = list(data, 3, 0, 2),
  mixed = list(data, 4, 1, 0.4),
  adverse = list(adverse, 3, 0, 0),
  ties = list(ties, 3, 0, 0)
)
for (name in names(cases)) {
  args <- cases[[name]]
  set.seed(431)
  do.call(baseline$merged.tree.make, args)
  old_rng <- .Random.seed
  set.seed(431)
  model <- do.call(fit_merged_tree, args)
  check_equal(model$nodes, baseline$merged.tree, paste(name, "전체 노드"))
  check_equal(.Random.seed, old_rng, paste(name, "난수 소비"))
  for (row in seq_len(nrow(args[[1]]))) {
    response <- args[[1]][row, , drop = FALSE]
    old_trace <- observed_predict(response)
    result <- predict_merged_tree(model, response)
    check_equal(result[c("node", "prediction", "stage")],
                list(node = baseline$now, prediction = baseline$now.pred, stage = baseline$now.stage),
                paste(name, row, "예측"))
    check_equal(result$path, old_trace$path, paste(name, row, "노드 경로"))
    check_equal(result$items, model$columns[as.numeric(old_trace$items)], paste(name, row, "문항 경로"))
  }
  combined <- sum(vapply(model$nodes, function(node) {
    # 실제 병합된 원래 노드의 개수를 세어 테스트 조건을 확인한다.
    node[[6]] == "combined"
  }, logical(1)))
  cat(sprintf("PASS %s: nodes=%d combined=%d rows=%d\n", name, length(model$nodes), combined, nrow(args[[1]])))
}

# 같은 fold·후보 순서와 시드로 교차검증 결과표 및 선택값을 비교한다.
check_cv <- function(parallel = FALSE, cluster = NULL) {
  folds <- split(seq_len(nrow(data)), rep(1:3, length.out = nrow(data)))
  set.seed(712)
  if (parallel) parallel::clusterSetRNGStream(cluster, 712)
  old <- baseline$cv.10fold.merge(data, folds, c(0, 0.5), c(0, 0.2), 3)
  old_rng <- .Random.seed
  set.seed(712)
  if (parallel) parallel::clusterSetRNGStream(cluster, 712)
  current <- cross_validate_merged_tree(data, folds, c(0, 0.5), c(0, 0.2), 3, parallel)
  check_equal(unname(as.matrix(current$results)), unname(as.matrix(baseline$cv.result)), "CV 결과표")
  check_equal(c(current$critical.t, current$critical.s), old, "CV 선택값")
  if (!parallel) check_equal(.Random.seed, old_rng, "CV 난수 소비")
  cat("PASS CV", if (parallel) "parallel" else "sequential", "\n")
}
check_cv()

for (name in c("small", "constant")) {
  boundary <- if (name == "small") data[1:4, ] else transform(data, score = 1)
  baseline$merged.tree.make(boundary, 3, 0, 0)
  model <- fit_merged_tree(boundary, 3, 0, 0)
  check_equal(model$nodes, baseline$merged.tree, paste(name, "루트"))
  original_error <- check_error(baseline$predict.merge(boundary[1, ]), paste(name, "기존 실패"))
  corrected <- predict_merged_tree(model, boundary[1, ])
  check_equal(corrected, list(node = 1L, prediction = mean(boundary$score), stage = 0,
                              path = 1L, items = character()), paste(name, "승인된 루트 수정"))
  cat("FIXED", name, ":", original_error, "-> root mean / zero items\n")
}
score_last <- data[, c(paste0("q", 1:5), "score")]
check_error(baseline$merged.tree.make(score_last, 3, 0, 0), "기존 열 순서 오류 재현")
check_error(fit_merged_tree(score_last, 3, 0, 0), "score 첫 열 조건")
check_error(fit_merged_tree(transform(data, q1 = NA_real_), 3, 0, 0), "결측치")
check_error(fit_merged_tree(transform(data, q1 = 2), 3, 0, 0), "비이진 응답")
check_error(fit_merged_tree(data, 0, 0, 0), "0단계")
check_error(cross_validate_merged_tree(data, list(integer()), 0, 0, 3), "빈 fold")
check_error(cross_validate_merged_tree(data, list(c(1, 1)), 0, 0, 3), "중복 fold")
check_error(cross_validate_merged_tree(data, list(1:3), 0, 0, 3, TRUE), "백엔드 미등록")

# 모형을 번갈아 사용해도 예측이 섞이지 않고 전역 모형·예측값이 생성되지 않는지 확인한다.
before <- intersect(c("merged.tree", "now", "now.pred", "now.stage", "cv.result", "final.t", "final.s"), ls(globalenv()))
first_model <- fit_merged_tree(data, 3, 0, 0)
first_prediction <- predict_merged_tree(first_model, data[1, ])
second_model <- fit_merged_tree(adverse, 2, 0, 0)
invisible(predict_merged_tree(second_model, adverse[1, ]))
check_equal(predict_merged_tree(first_model, data[1, ]), first_prediction, "모형 간 상태 분리")
check_equal(predict_merged_tree(first_model, data[1, first_model$features, drop = FALSE]),
            first_prediction, "예측 시 score 생략")
after <- intersect(c("merged.tree", "now", "now.pred", "now.stage", "cv.result", "final.t", "final.s"), ls(globalenv()))
check_equal(after, before, "전역 출력 없음")
check_error(predict_merged_tree(first_model, data[1, rev(first_model$features)]), "문항 순서 불일치")

# 루트 수정이 적용되는 상수 점수 CV와 동률 시 첫 후보 선택을 확인한다.
constant_cv <- cross_validate_merged_tree(transform(data, score = 1), list(1:30, 31:80),
                                          c(0.5, 0), c(0.2, 0), 3)
check_equal(constant_cv$results$mae, c(0, 0), "상수 점수 CV")
check_equal(c(constant_cv$critical.t, constant_cv$critical.s), c(0.5, 0.2), "CV 동률 순서")

# 요청한 경우에만 로컬 worker 2개를 만들고 종료한다. worker도 동일 라이브러리를 쓴다.
check_parallel <- function() {
  cluster <- parallel::makePSOCKcluster(2L, outfile = "")
  on.exit({ parallel::stopCluster(cluster); foreach::registerDoSEQ() }, add = TRUE)
  parallel::clusterCall(cluster, .libPaths, .libPaths())
  doParallel::registerDoParallel(cluster)
  check_cv(TRUE, cluster)
}
if ("--parallel" %in% commandArgs(trailingOnly = TRUE)) check_parallel()
cat("PASS total checks:", checks, "\n")
print(sessionInfo())
