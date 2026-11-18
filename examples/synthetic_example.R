# 저장소 루트에서 실행하는 합성자료 예제이다. 파일 저장·외부 통신·병렬 worker 생성은 하지 않는다.
source("R/config.R", encoding = "UTF-8")
source("R/merged_tree.R", encoding = "UTF-8")
source("R/cross_validation.R", encoding = "UTF-8")
source("examples/synthetic_data.R", encoding = "UTF-8")

set.seed(20261118)
data <- make_synthetic_data()
model <- fit_merged_tree(data, number = 3, critical.t = 0.5, critical.s = 0.2)
print(predict_merged_tree(model, data[1, model$features, drop = FALSE]))
folds <- split(sample(seq_len(nrow(data))), rep(1:3, length.out = nrow(data)))
result <- cross_validate_merged_tree(data, folds, c(0, 0.5), c(0, 0.2), number = 3)
print(result)
