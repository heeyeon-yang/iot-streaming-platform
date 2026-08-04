
## Milestone 3 디버깅 (이어서 진행, 해결됨)
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
