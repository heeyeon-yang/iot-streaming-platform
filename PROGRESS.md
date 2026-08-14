
## 2026-08-14 (금)
- **CI/CD OIDC 파이프라인 디버깅**
  - `AWS_ACCOUNT_ID` Secret 값 정상 동작 확인 (`Debug Role ARN` 스텝 마스킹 출력 확인)
  - OIDC AssumeRole 권한 에러(`sts:AssumeRoleWithWebIdentity`) 발생으로 보류
  - 추후 IAM Role Trust Policy 조건 및 OIDC Provider 설정 재검토 필요
