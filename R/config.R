# 기존 CART 분할 설정을 반환한다. 나머지 rpart 기본값은 해당 패키지 버전을 따른다.
merged_tree_control <- function() {
  list(minsplit = 6L, maxdepth = 1L, cp = 0)
}

# 필요한 패키지의 설치 여부를 확인한다. 설치나 검색 경로 변경은 수행하지 않는다.
act_require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("필요한 패키지를 설치하세요: ", paste(missing, collapse = ", "))
  invisible(TRUE)
}

# 학습 입력이 이름이 고유한 수치형 0/1 문항과 유한한 score로 구성되었는지 확인한다.
validate_training_data <- function(data) {
  if (!is.data.frame(data) || !nrow(data) || ncol(data) < 2L ||
      anyDuplicated(names(data)) || anyNA(names(data)) || any(!nzchar(names(data))) ||
      !"score" %in% names(data)) {
    stop("학습자료에는 행, 고유한 문항 열 이름, score 열이 필요합니다.")
  }
  if (names(data)[1] != "score") stop("기존 열 번호 규칙에 따라 score가 첫 열이어야 합니다.")
  for (name in names(data)) {
    values <- data[[name]]
    if (!is.numeric(values) || any(!is.finite(values))) {
      stop("모든 열은 결측치 없는 유한한 수치형이어야 합니다: ", name)
    }
    if (name != "score" && any(!values %in% c(0, 1))) {
      stop("문항 반응은 0 또는 1이어야 합니다: ", name)
    }
  }
  invisible(TRUE)
}

# 단계 수와 병합 기준이 지원 범위의 단일 수치인지 확인한다.
validate_tree_parameters <- function(number, critical.t, critical.s) {
  for (value in list(number, critical.t, critical.s)) {
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value)) {
      stop("단계 수와 병합 기준은 유한한 단일 수치여야 합니다.")
    }
  }
  if (number < 1 || number != floor(number) || critical.t < 0 || critical.s < 0) {
    stop("단계 수는 양의 정수, 병합 기준은 0 이상이어야 합니다.")
  }
  invisible(TRUE)
}

# 예측 응답 1행의 문항 이름과 순서 및 0/1 값을 확인한다. score는 생략 가능하다.
validate_response <- function(model, response) {
  if (!inherits(model, "act_merged_tree") || !is.data.frame(response) || nrow(response) != 1L ||
      anyDuplicated(names(response)) ||
      !identical(names(response)[names(response) != "score"], model$features)) {
    stop("응답은 학습 때와 같은 이름·순서의 문항을 가진 데이터프레임 1행이어야 합니다.")
  }
  for (name in model$features) {
    value <- response[[name]]
    if (!is.numeric(value) || length(value) != 1L || !is.finite(value) || !value %in% c(0, 1)) {
      stop("응답 문항은 결측치 없는 수치형 0/1이어야 합니다: ", name)
    }
  }
  invisible(TRUE)
}
