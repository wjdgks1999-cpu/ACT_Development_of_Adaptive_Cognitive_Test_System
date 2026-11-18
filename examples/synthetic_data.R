# 실제 문항·응시자료와 무관한 5개 이진 문항과 연속 점수를 만든다. 난수 시드는 호출자가 정한다.
make_synthetic_data <- function(repeats = 8L) {
  patterns <- expand.grid(q1 = 0:1, q2 = 0:1, q3 = 0:1, q4 = 0:1, q5 = 0:1)
  data <- patterns[rep(seq_len(nrow(patterns)), each = repeats), ]
  rownames(data) <- NULL
  data$score <- with(data, 5 * q1 + 3 * q2 + 2 * q3 + q4 + 0.6 * q5) +
    stats::rnorm(nrow(data), sd = 0.7)
  data[, c("score", paste0("q", 1:5))]
}
