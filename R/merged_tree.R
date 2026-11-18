# 기존 순서의 9개 필드를 가진 노드를 만든다. data와 그 score 평균을 함께 보관한다.
make_tree_node <- function(id, parents, split, data, stage, merged = NULL) {
  list(id, parents, split, data, "yes", "terminal", merged, stage, mean(data$score))
}

# 지정한 두 노드를 기존 순서대로 병합하고 원래 노드의 상태를 갱신한 트리를 반환한다.
merge_tree_nodes <- function(nodes, pair, stage) {
  first <- nodes[[pair[1]]]
  second <- nodes[[pair[2]]]
  nodes[[length(nodes) + 1L]] <- make_tree_node(
    length(nodes) + 1L, c(first[[2]], second[[2]]), c(first[[3]], second[[3]]),
    rbind(first[[4]], second[[4]]), stage, pair
  )
  for (id in pair) {
    nodes[[id]][[5]] <- "no"
    nodes[[id]][[6]] <- "combined"
  }
  nodes
}

# 기존 rpart 설정으로 한 단계 회귀트리를 학습해 party 객체로 변환한다.
fit_stump <- function(data) {
  tree <- rpart::rpart(score ~ ., data = data,
                       control = do.call(rpart::rpart.control, merged_tree_control()))
  partykit::as.party(tree)
}

# 두 노드의 score로 기존 절대 t 통계량 또는 psych의 Cohen's d를 계산한다.
node_pair_statistic <- function(first, second, method) {
  if (method == "t") return(abs(stats::t.test(first$score, second$score)$statistic))
  first_group <- as.data.frame(cbind(group = rep("A", nrow(first)), score = first$score))
  second_group <- as.data.frame(cbind(group = rep("B", nrow(second)), score = second$score))
  data <- rbind(first_group, second_group)
  data[, 2] <- as.numeric(data[, 2])
  abs(psych::cohen.d(data, group = "group")$cohen.d[2])
}

# 한 단계에서 지정한 기준의 병합을 반복한다. 동률이면 마지막 쌍을 고르는 순서를 보존한다.
merge_stage_nodes <- function(nodes, stage, threshold, method) {
  repeat {
    candidates <- which(vapply(nodes, function(node) {
      # 해당 단계에서 아직 분할·병합 가능한 노드인지 반환한다.
      node[[5]] == "yes"
    }, logical(1)))
    if (length(candidates) <= 1L) break
    values <- c()
    for (i in candidates) {
      first <- nodes[[i]][[4]]
      if (method == "t" && stats::sd(first$score) == 0) {
        nodes[[i]][[5]] <- "no"
        next
      }
      for (j in candidates[i < candidates]) {
        second <- nodes[[j]][[4]]
        if (method == "t" && stats::sd(second$score) == 0) {
          nodes[[j]][[5]] <- "no"
          next
        }
        values <- c(values, node_pair_statistic(first, second, method))
      }
    }
    if (!length(values) || min(values) > threshold) break
    minimum <- min(values)
    pair <- c()
    # 기존 구현처럼 같은 후보를 다시 순회한다. t 단계의 상태 갱신도 그대로 유지한다.
    for (i in candidates) {
      first <- nodes[[i]][[4]]
      if (method == "t" && stats::sd(first$score) == 0) {
        nodes[[i]][[5]] <- "no"
        next
      }
      for (j in candidates[i < candidates]) {
        second <- nodes[[j]][[4]]
        if (method == "t" && stats::sd(second$score) == 0) {
          nodes[[j]][[5]] <- "no"
          next
        }
        if (node_pair_statistic(first, second, method) == minimum) pair <- c(i, j)
      }
    }
    nodes <- merge_tree_nodes(nodes, pair, stage)
  }
  nodes
}

# 0/1 반응과 score로 병합 결정트리를 학습한다. 전역변수 대신 노드·열 정보·설정을 반환한다.
fit_merged_tree <- function(data, number, critical.t, critical.s) {
  validate_training_data(data)
  validate_tree_parameters(number, critical.t, critical.s)
  act_require_packages(c("rpart", "partykit", "psych"))
  nodes <- list(make_tree_node(1, NULL, NULL, data, 0))
  for (stage in seq_len(number)) {
    splitting <- which(vapply(nodes, function(node) {
      # 다음 분할 대상인 노드인지 반환한다.
      node[[5]] == "yes"
    }, logical(1)))
    for (id in splitting) {
      node_data <- nodes[[id]][[4]]
      nodes[[id]][[5]] <- "no"
      if (nrow(node_data) <= 5L) next
      nodes[[id]][[6]] <- "interval"
      # 원본의 사전 분할과 실제 분할 호출을 모두 유지해 난수 소비 순서를 보존한다.
      preliminary <- fit_stump(node_data)
      if (grid::depth(preliminary) == 0) {
        nodes[[id]][[6]] <- "terminal"
        next
      }
      repeat {
        tree <- fit_stump(node_data)
        if (grid::depth(tree) == 0) {
          nodes[[id]][[6]] <- "terminal"
          break
        }
        split <- as.list(partykit::node_party(tree))[[1]]$split
        varid <- split$varid
        standard <- split$breaks
        under <- node_data[node_data[, varid] < standard, ]
        upper <- node_data[node_data[, varid] >= standard, ]
        if (mean(under$score) >= mean(upper$score)) {
          node_data[, varid] <- 0
          next
        }
        break
      }
      if (grid::depth(tree) == 0) {
        nodes[[id]][[6]] <- "terminal"
        next
      }
      nodes[[length(nodes) + 1L]] <- make_tree_node(
        length(nodes) + 1L, id, c(varid, standard, "under"), under, stage
      )
      nodes[[length(nodes) + 1L]] <- make_tree_node(
        length(nodes) + 1L, id, c(varid, standard, "upper"), upper, stage
      )
    }
    nodes <- merge_stage_nodes(nodes, stage, critical.t, "t")
    nodes <- merge_stage_nodes(nodes, stage, critical.s, "d")
  }
  structure(list(nodes = nodes, columns = names(data),
                 features = names(data)[names(data) != "score"],
                 parameters = list(number = number, critical.t = critical.t, critical.s = critical.s)),
            class = "act_merged_tree")
}

# 응답 1행의 분기·병합 경로를 따라 최종 노드, 점수, 단계 및 방문 경로를 반환한다.
predict_merged_tree <- function(model, response) {
  validate_response(model, response)
  nodes <- model$nodes
  now <- 1L
  prediction <- nodes[[now]][[9]]
  stage <- 0
  path <- now
  items <- character()
  # 승인된 오류 수정: 분할되지 않은 루트에서는 문항 없이 학습 점수 평균을 반환한다.
  if (nodes[[now]][[6]] == "terminal") {
    return(list(node = now, prediction = prediction, stage = stage, path = path, items = items))
  }
  repeat {
    candidates <- which(vapply(nodes, function(node) {
      # 직접 분할로 생성된 자식인지 판별하고 병합 노드는 제외한다.
      now %in% node[[2]] && length(node[[3]]) == 3L
    }, logical(1)))
    split <- nodes[[candidates[1]]][[3]]
    item <- model$columns[as.numeric(split[1])]
    items <- c(items, item)
    # 0/1 입력 범위에서 원본의 비교와 동일한 분기를 사용한다.
    direction <- if (response[[item]] < split[2]) "under" else "upper"
    for (id in candidates) {
      if (nodes[[id]][[3]][3] == direction) {
        now <- id
        prediction <- nodes[[id]][[9]]
        stage <- nodes[[id]][[8]]
        path <- c(path, now)
      }
    }
    if (nodes[[now]][[6]] == "combined") {
      for (id in seq_along(nodes)) {
        if (now %in% nodes[[id]][[7]]) {
          now <- id
          prediction <- nodes[[id]][[9]]
          stage <- nodes[[id]][[8]]
          path <- c(path, now)
        }
      }
    }
    if (nodes[[now]][[6]] == "terminal") break
  }
  list(node = now, prediction = prediction, stage = stage, path = path, items = items)
}
