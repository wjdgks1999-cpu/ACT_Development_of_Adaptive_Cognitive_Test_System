# ACT 코드 정리 검증

검증일: 2026-11-18. 이번 정리는 공개된 핵심 함수의 유지보수 작업이며, 과거 프로젝트의 신규 실적이나 과거 성능 재현을 의미하지 않는다.

## 범위와 승인된 결정

- 기준 커밋: `6e77f884217efc47d1d55a496e360592e76165e9`.
- 원본: `Merged_Decision_Tree_구현_Code.r`, blob `8e39f0cb147b0efbc769794a3900f2577adc71fe`.
- 보안상 핵심 함수만 공개된 저장소이며, 외부 호출 스크립트가 없음을 사용자에게 확인했다. 전역변수와 기존 함수명에 대한 호환 계층은 만들지 않는다.
- 지원 입력은 결측치 없는 수치형 0/1 문항과 유한한 수치형 `score`이다. `score`를 첫 열로 제한하고 검증하는 방향을 사용자가 선택했다.
- 루트 단독 모형의 예측 오류는 원본에서 재현한 뒤 평균 점수·0문항 반환으로 수정하도록 승인받았다.
- 실제자료·과거 모형·fold·당시 실행 환경이 없으므로 새 환경의 합성자료로 검증하고 실제자료 검증은 미검증으로 남긴다.
- 기존 폴더명과 이미지 2개는 유지한다. reference는 읽기 근거로만 사용했으며 비공개 원문·문항·응시자료를 옮기지 않았다.

## 정적 확인 및 변경

원본 최상위의 학습·예측 함수와 교차검증 내부의 학습·예측 함수는 주석과 공백을 제외하면 일치했다. 이를 `R/merged_tree.R`로 통합했다. 노드 생성·병합과 두 병합 단계의 공통 순회를 함수로 분리하고, `R/config.R`에 기존 CART 설정과 입력 검증을 모았다.

`R/cross_validation.R`은 공통 학습·예측 함수의 반환값을 사용한다. 학습과 예측의 `<<-` 출력은 제거했고, 노드는 기존 9개 필드 순서를 유지한다. `grid::depth`, `partykit::as.party`, `psych::cohen.d` 등은 실제 원본 실행에서 사용된 함수를 명시적으로 호출한다. 패키지 부착 순서에 의존하지 않는다.

| 기존 호출·출력 | 정리 후 호출·출력 |
| --- | --- |
| `merged.tree.make(...)` → 외부 `merged.tree` | `fit_merged_tree(...)` → `model`, 기존 노드는 `model$nodes` |
| `predict.merge(response)` → 외부 `now`, `now.pred`, `now.stage` | `predict_merged_tree(model, response)` → `node`, `prediction`, `stage`, `path`, `items` |
| `cv.10fold.merge(...)` → 외부 결과와 선택값 | `cross_validate_merged_tree(...)` → `results`, `critical.t`, `critical.s` |

원본 단일 파일은 대체 구현의 비교 검증 후 제거했다. 비교 테스트는 고정된 Git 커밋에서 원본을 읽으므로 복제 코드나 호환 파일을 저장소에 남기지 않는다. 기준 커밋 객체가 없는 얕은 복제에서는 회귀 비교를 실행할 수 없다.

## 실행 환경과 부작용

Windows 11 x64에서 R 4.6.2 UCRT를 사용했다. 과거 실행 환경을 복원한 것이 아니다.

| 패키지 | 검증 버전 | 사용 |
| --- | --- | --- |
| rpart | 4.1.27 | 분할 |
| partykit | 1.3-2 | 트리 변환·분할 정보 |
| psych | 2.6.9 | Cohen's d |
| caret | 7.1-0 | MAE |
| foreach | 1.5.2 | 교차검증 반복 |
| party | 1.3-23 | 원본 비교 환경 |
| doParallel | 1.0.17 | 2-worker 비교 |

R은 [공식 CRAN 배포본](https://cran.r-project.org/bin/windows/base/)을 내려받아 체크섬 `d01b7413cce5540a35eaf8295ef32197`과 일치함을 확인하고, [innoextract](https://constexpr.org/innoextract/)로 상위 작업 폴더의 `.runtime/R/app`에 추출했다. Windows 설치 프로그램은 실행하지 않았다. 패키지는 `.runtime/library`에 설치했다. 다운로드·설치에서만 외부 통신을 사용했다. R 및 패키지 파일은 Git 저장소 밖에 있다.

호스트에서 전달된 `C.UTF-8` locale은 이 Windows R 실행에서 실패했으므로 실행 프로세스에 `LC_ALL=English_United States.utf8`, `LANG=en_US.UTF-8`를 지정했다. 시스템의 영구 환경변수는 변경하지 않았다.

기본 예제·회귀 테스트는 자료와 모형을 메모리에서 생성한다. 병렬 테스트는 `--parallel`로 요청한 경우에만 로컬 PSOCK worker 2개를 생성하고 종료 시 정리한다. 운영 코드의 병렬 실행은 호출자가 등록한 백엔드를 사용하며 worker를 자동 생성하지 않는다. 원본 함수의 `<<-` 쓰기는 테스트 전용 환경에 격리한다.

## 동작 보존 비교

`tests/regression.R`은 실제 문항과 무관한 5개 0/1 문항·256행을 만든다. 자료 생성 시드는 9127, 각 원본·정리본 학습 시작 시드는 431로 고정한다. 각 조건의 모든 응답에 대해 전체 노드 필드와 학습 행, 최종 노드·점수·단계, 방문 노드 및 문항 경로를 비교한다. 원본 예측 함수에는 경로 기록만 추가하고 분기·계산은 바꾸지 않았다. 비교 허용오차는 0이다.

| 합성 조건 | 노드 수 | 병합된 원래 노드 수 | 비교 결과 |
| --- | ---: | ---: | --- |
| 병합 없음 | 15 | 0 | 일치 |
| t 기준 병합 | 10 | 6 | 일치 |
| Cohen's d 기준 병합 | 16 | 6 | 일치 |
| 혼합 병합 | 32 | 6 | 일치 |
| 정답 집단 점수가 낮은 문항 제외 | 13 | 0 | 일치 |
| 병합 기준 0에서 동률 처리 | 16 | 6 | 일치 |

위 6개 조건의 난수 상태도 학습 후 일치했다. 사전 분할과 실제 분할의 중복 호출은 원본 난수 소비 순서를 유지하기 위해 보존했다. 분할 설정, t 다음 d 병합 순서, 병합 통계량 동률의 마지막 쌍 선택, 병합 이동·종료 규칙을 유지했다.

교차검증은 3개 외부 fold(86·85·85행), t 후보 `c(0, 0.5)`, d 후보 `c(0, 0.2)`, 최대 3단계로 비교했다. 원본·정리본의 결과표와 선택값이 순차 실행 및 2-worker 실행에서 일치했다. 순차 실행은 시드 712와 실행 후 난수 상태를 비교했고, 병렬 실행은 각 비교 직전 동일 worker에 `clusterSetRNGStream(..., 712)`를 적용했다. 평가 기준은 fold별 MAE의 단순 평균을 보존했다.

모형을 번갈아 예측해도 결과가 섞이지 않는 것, 전역 출력 변수가 생기지 않는 것, 예측 입력에서 score 생략, 잘못된 문항 순서·결측치·비이진 값·0단계·빈/중복 fold 거부도 검증한다.

최종 실행에서 `tests/regression.R --parallel`은 종료 코드 0으로 **4,645개 비교·검증 항목**을 통과했다. 이 수는 행별 점수·경로 비교를 포함한 assertion 수이며 독립된 데이터셋이나 실험 수가 아니다. 별도의 새 R 프로세스에서 `examples/synthetic_example.R`도 종료 코드 0으로 실행했다. 테스트 종료 후 worker가 남지 않았음을 확인했다. `git diff --check`도 통과했다.

## 승인된 동작 차이

### score 열 순서 검증

`partykit` 트리의 데이터는 `score`가 첫 열이며 원본은 그 변수 번호로 입력자료를 직접 인덱싱한다. 합성자료의 score를 마지막 열에 놓으면 원본 학습에서 `missing value where TRUE/FALSE needed` 오류가 재현됐다.

열 번호 연결 방식을 바꾸지 않고, 첫 열이 score가 아니면 학습 전에 명확한 오류를 반환한다. 입력을 자동 재정렬하지 않는다. 기존 정상 조건인 score 첫 열 입력의 결과는 위와 같이 비교했다.

### 루트 단독 예측

4행 학습자료 및 score가 모두 1인 자료로 루트 단독 모형을 만들었다. 원본은 예측 시 `attempt to select less than one element in get1index` 오류가 발생했다. 정리본은 루트 평균 점수, 단계 0, 빈 문항 경로, 방문 노드 1을 반환한다. 학습된 노드 자체는 원본과 동일하다.

따라서 이 조건은 원본과 예측 결과가 동일하다고 표현하지 않는다. 기존 실패를 정상 반환으로 바꾼 승인된 오류 수정이다. 상수 점수 자료의 교차검증도 이제 MAE 0으로 끝나며, 동률일 때 후보 벡터의 첫 값을 선택한다.

## 재실행

저장소 루트에서 필요한 패키지를 준비한다. 자동 설치는 테스트에 포함하지 않는다.

```r
install.packages(c("rpart", "party", "partykit", "psych", "caret", "foreach", "doParallel"))
```

```text
Rscript --vanilla tests/regression.R
Rscript --vanilla tests/regression.R --parallel
Rscript --vanilla examples/synthetic_example.R
```

현재 작업 폴더의 로컬 환경은 PowerShell에서 다음과 같이 실행한다.

```powershell
$env:R_LIBS_USER = (Resolve-Path ..\.runtime\library).Path
$env:LC_ALL = 'English_United States.utf8'
$env:LANG = 'en_US.UTF-8'
& ..\.runtime\R\app\bin\Rscript.exe --vanilla tests\regression.R --parallel
```

## 미검증 범위

- 실제 응시자료, 최종 영역별 모형, 당시 fold·패키지 버전이 없어 실제자료 동등성 및 과거 상관계수·MAE·RMSE는 재현하지 않았다.
- 합성자료 일치는 모든 입력에서의 동등성 증명이나 예측 성능 개선을 뜻하지 않는다.
- 다른 OS·R/패키지 버전, 대규모 자료, 다른 병렬 백엔드·worker 수·작업 배치의 재현성은 확인하지 않았다.
- 결측 반응과 비이진 문항은 지원 범위 밖이다. 새 보정·대체·검사 알고리즘을 추가하지 않았다.
- 전체 상용 검사 UI·문항은행·운영 정책·개인정보 처리 시스템의 검증은 공개 코드 범위 밖이다.
