## Milestone 3 디버깅 (이어서 진행)
- ECR push 중 네트워크 끊김 발생함 (프록시 환경 특성으로 추정) -> 재시도하면 기존 레이어는 스킵되고 이어짐, 별도 조치 불필요
- print 로그가 kubectl logs에 하나도 안 찍히는 문제
  -> Dockerfile에 PYTHONUNBUFFERED=1 빠져있었음. 컨테이너 환경에서 stdout이 블록 버퍼링되면서 로그가 버퍼에 쌓이기만 하고 안 나갔던 것
  -> stream-processor, alerting-service 둘 다 Dockerfile에 추가
- simulator.sh가 요청을 보내도 ingestion-api에 아무 흔적이 없는 문제
  -> simulator.sh는 localhost:3000으로 요청하는데 port-forward를 8080:80으로 열어서 애초에 요청이 안 갔음
  -> port-forward는 3000:80으로 열 것: kubectl port-forward -n iot-streaming svc/ingestion-api 3000:80
- stream-processor에서 DynamoDB PutItem이 계속 ValidationException(device_id 없음)으로 실패하는 문제
  -> ingestion-api(Node)는 camelCase(deviceId, sensorType) + ISO timestamp 문자열로 Kinesis에 씀
  -> DynamoDB 테이블은 snake_case(device_id, sensor_type), timestamp는 숫자(N) range key
  -> stream-processor의 process_record()에서 키 변환 + timestamp를 epoch 초로 변환하도록 수정. 테이블 스키마는 안 건드림
- 위 세 가지 고치고 나서 파이프라인 전체 확인됨: ingestion-api -> Kinesis -> stream-processor -> DynamoDB (20건 저장 확인)
- alerting-service threshold 로직도 확인함 (temperature=85 수동 전송 시 정상 트리거)
  Slack 전송은 404 에러 나는데 이건 webhook이 아직 placeholder라 의도된 상태

## 남은 이슈
- Slack Webhook 아직 미발급, 발급되면 secret 값 교체
- alerting-service 알림 중복 발생 가능성 있음 (LATEST iterator + 5초 폴링 경계에서 같은 record 두 번 잡힘) -> sequence number 기억해서 dedup 필요, 아직 미처리
- (Phase 2 후순위) ArgoCD, Prometheus/Grafana

## Terraform state 분리 (ECR 별도 관리)
- 문제: terraform destroy 시 aws_ecr_repository도 같이 삭제되어 매 세션마다 이미지 재빌드/재푸시 필요했음
- 해결: ECR 관련 리소스(aws_ecr_repository.services, aws_ecr_lifecycle_policy.services)를
  terraform/ecr.tf에서 별도 디렉토리 terraform-ecr/로 분리
- terraform state mv로 기존 리소스를 새 state로 이동 (실제 AWS 자원은 재생성 없이 그대로 유지, 이미지도 안 날아감)
- 앞으로 세션 루틴:
  - 시작: terraform/ 에서만 terraform apply (EKS, VPC, Kinesis, DynamoDB)
  - 종료: terraform/ 에서만 terraform destroy
  - terraform-ecr/ 는 프로젝트 끝날 때까지 destroy 하지 않음
- 코드 안 바뀐 서비스는 이제 재빌드/재푸시 불필요 (이미지가 ECR에 계속 남아있음)

## Alerting 중복 알림 dedup 처리
- 원인: kubectl rollout restart 시 old/new 파드가 잠깐 동시에 떠 있는 동안,
  둘 다 독립적으로 LATEST shard iterator를 얻어와서 겹치는 시간대 record를 각자 처리 -> 중복 알림
- 해결: alerting-service main.py에 SequenceNumber 기준 in-memory dedup 추가
  (deque + set, 최근 500개 기억, 이미 처리한 sequence number는 skip)
- 단일 프로세스 재시작(크래시 등)에는 영향 없음 - 그 경우 파드가 겹치지 않으므로 애초에 중복 위험 없음
- 완전한 크로스 프로세스 dedup(DynamoDB 조건부 쓰기)은 포트폴리오 규모에서 과함 -> 인메모리 방식으로 충분하다고 판단
- 검증: temperature=85 수동 전송 -> 경고 로그 1회만 출력 확인

## Slack Webhook 연동
- Slack app 생성 -> Incoming Webhooks 활성화 -> #iot-alerts 채널에 연동
- k8s/secret-alerting.yaml의 SLACK_WEBHOOK_URL을 실제 값으로 교체 (base64 -w 0 사용, 개행 포함 시 sed 깨지는 이슈 있었음)
- secret-alerting.yaml은 git에 커밋된 적 있었으나 placeholder 값만 올라가 있었음 확인 후
  git rm --cached로 추적 해제, .gitignore에 추가하여 앞으로 실제 값 노출 방지
- 검증: temperature=85 수동 전송 -> #iot-alerts 채널에 정상 수신 확인

## Milestone 3 마무리
- 파이프라인 전체(ingestion-api -> Kinesis -> stream-processor -> DynamoDB -> alerting-service -> Slack) 정상 동작 확인
- ECR state 분리로 세션 재시작 루틴 안정화

## read-api DynamoDB 연동
- 기존 코드는 mock 데이터 반환하는 placeholder 상태였음 (대시보드 프론트엔드 개발용으로 의도된 것)
- @aws-sdk/client-dynamodb, @aws-sdk/lib-dynamodb 추가
- /readings: deviceId 쿼리 파라미터 있으면 QueryCommand, 없으면 ScanCommand
- /devices: ScanCommand + ProjectionExpression으로 device_id만 추출, Set으로 중복 제거
- 검증 중 발견: sensor-readings 테이블이 ECR과 달리 별도 state로 분리 안 되어 있어서
  terraform destroy/apply 사이클마다 테이블이 비워짐 -> simulator.sh로 재시딩 후 20건 정상 조회 확인
- 참고: dynamodb 테이블도 ECR처럼 별도 state로 분리할지는 아직 미정 (테스트 데이터라 매번 새로 채워도 되는 관점도 있음)

## 세션 재개 후 재검증
- terraform apply로 인프라 재생성, k8s/ 재배포
- namespace.yaml이 없어서 kubectl create namespace 수동 실행 필요했음 (다음에 k8s/에 추가 고려)
- DynamoDB state 분리는 보류. 테스트 데이터라 재시딩으로 충분
- simulator.sh 재시딩 후 read-api 조회 정상 (38건)

## 2026-08-12
- ArgoCD 설치 중 application-controller가 Pending 상태로 고립 -> describe 확인해보니 Too many pods 에러 (CPU/RAM 부족이 아니라 t3.small 노드당 max pods(11개) 제한)
- rollout restart 하다 생긴 중복 ReplicaSet 정리 (kubectl rollout undo)
- 리소스 절약 위해 dex-server, notifications, applicationset 제외하고 argocd-cm 패치

## 2026-08-13
- t3.small 노드 파드 제한(11개)로 ArgoCD 설치 중 계속 Too many pods 발생
  -> AWS VPC CNI Prefix Delegation 적용 (ENABLE_PREFIX_DELEGATION=true, WARM_PREFIX_TARGET=1), aws-node 재시작 후 노드당 max pods 110개로 확장 확인

## 2026-08-14
- CI/CD OIDC 파이프라인 디버깅. AWS_ACCOUNT_ID secret 값은 정상인데 sts:AssumeRoleWithWebIdentity 에러로 보류
- IAM Role Trust Policy 조건이랑 OIDC Provider 설정 재검토 필요로 남겨둠

## ArgoCD 배포 검증
- application.yaml 적용해도 SYNC/HEALTH 계속 Unknown, 파드 안 뜸 -> core-install은 default AppProject 자동 생성 안 함. 수동 생성 후 정상 sync
- 파드 이미지가 <AWS_ACCOUNT_ID>...:latest로 그대로 뜸 -> base/deployments.yaml에 <AWS_ACCOUNT_ID>가 리터럴로 박혀 있어서 kustomize images 트랜스포머 name 매칭 실패. 실제 계정 ID로 치환
- alerting-service가 secret "alerting-secrets" not found로 계속 실패
  -> secret-alerting.yaml이 kustomization.yaml resources 목록에서 누락돼 있었음. 추가해서 해결
  -> 이 과정에서 secret-alerting.yaml에 Slack Webhook 실제 값이 base64로 git에 커밋된 상태였던 것 발견 (public repo). Slack에서 webhook 재발급 완료
- 새 파드가 Too many pods로 계속 Pending -> 구버전 ReplicaSet이 슬롯 점유 중 + t3.small 파드 상한 근접. 구버전 ReplicaSet 스케일다운, 미사용 argocd-applicationset-controller도 스케일다운, prefix delegation 재적용으로 해결
- 네 서비스 전부 Running 확인, Application Synced/Healthy 확인

## CI/CD OIDC 및 kustomize image path 수정
- 8/14에 보류했던 sts:AssumeRoleWithWebIdentity 에러 -> IAM Role Trust Policy의 sub claim 조건이 계정/repo ID 포함하도록 업데이트 (terraform-ecr/github-oidc.tf 반영)해서 해결
- run #4(트리거용 커밋)에서 OIDC는 통과했는데 "Update Manifests Repo" 스텝의 kustomize edit set image에서 실패 -> 이미지 경로 수정
- run #5에서 build-and-deploy.yml 전체 성공 확인 (ECR push -> manifests repo 이미지 태그 커밋까지 end-to-end)
